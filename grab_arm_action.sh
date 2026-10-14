#!/bin/bash
# Oracle Free Tier ARM 抢机脚本 —— 供 GitHub Actions 调用
# 特性：
#   1) 自适应调速：被 API 限速(429/Throttling)时自动拉大间隔退避，避免触发风控封号；
#      正常缺货时保持紧凑节奏（5s），不浪费窗口。
#   1b) 尝试次数自动调整：单轮时间预算(默认210s) + 连续限流上限(默认3次)双保险，
#       限流严重时提前收工，畅通时打满 MAX_ATTEMPTS——无需手改次数。
#   2) 容量预检（Compute Capacity Report）：每轮先问 Oracle 当前 AD 是否有 A1 容量，
#      仅当明确报 OUT_OF_HOST_CAPACITY 且开启 STRICT_SKIP 才跳过本轮，
#      默认关闭严格跳过（只记录日志），避免误杀真实可用窗口。
#   3) 全 AD 扫描 + 跨 AD 切换（MULTI_AD）：动态列出 tenancy 下所有 AD 并逐个探测容量，
#      主 AD 无货但备用 AD 有货时，自动切换到有货 AD（需该 AD 有可用子网）。
set -u

export SUPPRESS_LABEL_WARNING=True
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
export OCI_CONFIG_FILE=$HOME/.oci/config

DISPLAY_NAME="arm"
OCPUS=2
MEMORY=12
BOOT_SIZE=100

MAX_ATTEMPTS="${MAX_ATTEMPTS:-10}"   # 单轮尝试次数上限（硬顶）
TIME_BUDGET="${TIME_BUDGET:-210}"    # 单轮时间预算(秒)：到点自动收工，保证跑进 5 分钟调度间隔
MAX_THROTTLE_STREAK="${MAX_THROTTLE_STREAK:-3}"  # 连续被限流上限：超过说明 OCI 在压速率，提前收工
INTERVAL=8                          # 当前尝试间隔（秒），自适应调整
MIN_INTERVAL=5
MAX_INTERVAL=120                    # 退避上限

ADAPTIVE="${ADAPTIVE:-true}"            # 自适应调速开关
CAPACITY_PRECHECK="${CAPACITY_PRECHECK:-true}"  # 容量预检开关
STRICT_SKIP="${STRICT_SKIP:-false}"     # 仅在明确无容量时跳过（默认关，避免误杀）
MULTI_AD="${MULTI_AD:-true}"            # 全 AD 扫描 + 跨 AD 切换开关

SSH_FILE=$HOME/id_rsa.pub
printf '%s\n' "${SSH_KEY_PUB:-}" > "$SSH_FILE"
chmod 600 "$SSH_FILE"

send_notify() {
  if [ -n "${SCT_KEY:-}" ]; then
    curl -s -X POST "https://sctapi.ftqq.com/${SCT_KEY}.send" \
      --data-urlencode "title=$1" --data-urlencode "desp=$2" >/dev/null 2>&1
  fi
}

# 查询实例公网 IP（无实例/未分配时输出空）
# 注意：Instance 对象没有 primary-public-ip 字段，必须走
# vnic-attachment(拿 vnic-id) -> vnic get(拿 public-ip)，否则永远返回空。
query_ip() {
  local iid vnic
  iid=$(oci --no-retry compute instance list --compartment-id "$COMPARTMENT_ID" \
        --display-name "$DISPLAY_NAME" --query 'data[0].id' --raw-output 2>/dev/null)
  [ -n "$iid" ] && [ "$iid" != "None" ] || return 0
  vnic=$(oci --no-retry compute vnic-attachment list --compartment-id "$COMPARTMENT_ID" \
         --instance-id "$iid" --query 'data[0]."vnic-id"' --raw-output 2>/dev/null)
  [ -n "$vnic" ] && [ "$vnic" != "None" ] || return 0
  oci --no-retry network vnic get --vnic-id "$vnic" --query 'data."public-ip"' --raw-output 2>/dev/null
}

echo "== 预检：是否已有运行中的实例 =="
EXISTING=$(oci --no-retry compute instance list \
  --compartment-id "$COMPARTMENT_ID" \
  --display-name "$DISPLAY_NAME" \
  --lifecycle-state RUNNING \
  --query 'data[0].id' --raw-output 2>/dev/null)
if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
  echo "已存在运行中的实例 $EXISTING，跳过。"
  send_notify "ARM实例已存在" "实例ID: $EXISTING"
  exit 0
fi

# 容量预检：调用 OCI Capacity Report，返回 readiness 状态字符串（失败返回 UNKNOWN）
# A1.Flex 是弹性规格，必须带 instance_shape_config（ocpu/内存）才能算出容量。
cap_status_for_ad() {
  local ad="$1"
  [ "$CAPACITY_PRECHECK" = "true" ] || { echo "DISABLED"; return; }
  OCPUS="$OCPUS" MEMORY="$MEMORY" \
  AVAILABILITY_DOMAIN="$ad" COMPARTMENT_ID="$COMPARTMENT_ID" \
  python3 - <<'PY'
import sys, os, oci
try:
    cfg = oci.config.from_file()
    core = oci.core.ComputeClient(cfg)
    ocpus = int(os.environ["OCPUS"]); mem = int(os.environ["MEMORY"])
    sc_cls = getattr(oci.core.models, "CapacityReportInstanceShapeConfig", None)
    sc = sc_cls(ocpus=ocpus, memory_in_gbs=mem) if sc_cls else None
    sa = oci.core.models.CreateCapacityReportShapeAvailabilityDetails(
        instance_shape="VM.Standard.A1.Flex",
        instance_shape_config=sc) if sc is not None \
        else oci.core.models.CreateCapacityReportShapeAvailabilityDetails(
        instance_shape="VM.Standard.A1.Flex")
    details = oci.core.models.CreateComputeCapacityReportDetails(
        compartment_id=os.environ["COMPARTMENT_ID"],
        availability_domain=os.environ["AVAILABILITY_DOMAIN"],
        shape_availabilities=[sa])
    rep = core.create_compute_capacity_report(create_compute_capacity_report_details=details)
    sas = getattr(rep.data, "shape_availabilities", None)
    st = sas[0].availability_status if sas else "UNKNOWN"
    sys.stderr.write("CAP_STATUS=%s\n" % st)
    print(st if st else "UNKNOWN")
except Exception as e:
    sys.stderr.write("CAP_ERR %s: %s\n" % (type(e).__name__, str(e)[:400]))
    print("UNKNOWN")
PY
}

CAP=$(cap_status_for_ad "$AVAILABILITY_DOMAIN")
echo "== 容量预检状态(主AD): ${CAP:-UNKNOWN} =="
if [ "$STRICT_SKIP" = "true" ] && [ "$CAP" = "OUT_OF_HOST_CAPACITY" ]; then
  echo "明确无容量且严格模式开启，跳过本轮以省调用。"
  exit 0
fi
# 优化：仅当报告 AVAILABLE 时本轮加量抓窗口。
# OUT_OF_HOST_CAPACITY 常是"假阴性"（报告滞后），故不据此减尝试次数，避免漏掉真实窗口。
if [ "$CAP" = "AVAILABLE" ]; then
  MAX_ATTEMPTS=$((MAX_ATTEMPTS + 5))
  echo "预检显示有容量，本轮加量到 $MAX_ATTEMPTS 次尝试。"
fi

# ===== 全 AD 扫描 + 跨 AD 切换 =====
# 动态列出 tenancy 下所有 AD（不硬编码 AD 名），逐个探测 A1.Flex 容量。
# 主 AD 无货但备用 AD 有货时切换目标；找不到子网则只告警、维持主 AD。
ALT_AD=""
TARGET_AD="$AVAILABILITY_DOMAIN"
TARGET_SUBNET="$SUBNET_ID"

find_subnet_in_ad() {
  # 在指定 AD 中找可用子网；主子网若是区域性子网(REGIONAL)则任何 AD 可用
  local ad="$1" vcn scope
  vcn=$(oci network subnet get --subnet-id "$SUBNET_ID" \
        --query 'data."vcn-id"' --raw-output 2>/dev/null)
  [ -n "$vcn" ] && [ "$vcn" != "None" ] || return 0
  scope=$(oci network subnet get --subnet-id "$SUBNET_ID" \
          --query 'data.scope' --raw-output 2>/dev/null)
  if [ "$scope" = "REGIONAL" ]; then
    echo "$SUBNET_ID"; return 0
  fi
  oci network subnet list --compartment-id "$COMPARTMENT_ID" --vcn-id "$vcn" \
    --query "data[?\"availability-domain\"=='$ad'].id | [0]" --raw-output 2>/dev/null
}

if [ "$MULTI_AD" = "true" ]; then
  # 用 --output json + python 解析，规避 --raw-output 对数组的格式怪癖
  # （实测 --raw-output 会输出带引号/括号的 JSON 数组，导致 AD 名非法）
  ALL_ADS=$(oci iam availability-domain list --compartment-id "$COMPARTMENT_ID" \
            --output json 2>/dev/null \
            | python3 -c "import sys,json
try:
    [print(a['name']) for a in json.load(sys.stdin).get('data',[])]
except Exception:
    pass")
  if [ -z "$ALL_ADS" ]; then
    echo "（AD 列表获取失败，跳过全 AD 扫描）"
  else
    echo "== 全 AD 容量扫描 =="
    for ad in $ALL_ADS; do
      st=$(cap_status_for_ad "$ad" 2>/dev/null)
      echo "  AD_STATUS:${ad}:${st}"
      if [ "$st" = "AVAILABLE" ] && [ "$ad" != "$AVAILABILITY_DOMAIN" ]; then
        ALT_AD="$ad"
      fi
    done
  fi
fi

if [ -n "$ALT_AD" ] && [ "$CAP" = "OUT_OF_HOST_CAPACITY" ]; then
  echo "== 发现备用 AD 有容量: $ALT_AD，尝试切换 =="
  ALT_SUBNET=$(find_subnet_in_ad "$ALT_AD")
  if [ -n "$ALT_SUBNET" ] && [ "$ALT_SUBNET" != "None" ]; then
    TARGET_AD="$ALT_AD"
    TARGET_SUBNET="$ALT_SUBNET"
    MAX_ATTEMPTS=$((MAX_ATTEMPTS + 5))
    echo "== 已切换目标: $TARGET_AD（子网 $TARGET_SUBNET），本轮加量到 $MAX_ATTEMPTS 次 =="
    send_notify "ARM备用AD有货" "主AD无货，已切换目标: $TARGET_AD"
  else
    echo "== 备用 AD $ALT_AD 有货但无可用子网，维持主 AD =="
    send_notify "ARM备用AD有货(无子网)" "$ALT_AD 有容量但该AD无子网，需手工创建后重启抢机"
  fi
fi

i=0
THROTTLE_STREAK=0
START_TS=$(date +%s)
while [ "$i" -lt "$MAX_ATTEMPTS" ]; do
  # 自动调整之一：时间预算。无论还剩多少次，到点就收工，
  # 保证单轮稳定跑进 5 分钟调度间隔内（job 超时 6 分钟，留足 setup 余量）。
  ELAPSED=$(( $(date +%s) - START_TS ))
  if [ "$ELAPSED" -ge "$TIME_BUDGET" ]; then
    echo "  已跑 ${ELAPSED}s，达到单轮时间预算 ${TIME_BUDGET}s，提前收工。"
    break
  fi
  i=$((i+1))
  TS=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$TS] 第 $i/$MAX_ATTEMPTS 次尝试（目标 $TARGET_AD，间隔 ${INTERVAL}s，已用 ${ELAPSED}s）..."

  RESULT=$(oci --no-retry compute instance launch --output json \
    --availability-domain "$TARGET_AD" \
    --compartment-id "$COMPARTMENT_ID" \
    --shape "VM.Standard.A1.Flex" \
    --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY}" \
    --display-name "$DISPLAY_NAME" \
    --image-id "$IMAGE_ID" \
    --boot-volume-size-in-gbs "$BOOT_SIZE" \
    --subnet-id "$TARGET_SUBNET" \
    --assign-public-ip true \
    --ssh-authorized-keys-file "$SSH_FILE" 2>&1)

  if echo "$RESULT" | grep -qiE "Out of host capacity|Out of capacity"; then
    echo "  没货，保持紧凑节奏。"
    THROTTLE_STREAK=0
    [ "$ADAPTIVE" = "true" ] && INTERVAL=$MIN_INTERVAL
  elif echo "$RESULT" | grep -qiE "LimitExceeded"; then
    echo "  配额异常，复检是否已有实例..."
    sleep 5
    EX=$(oci --no-retry compute instance list --compartment-id "$COMPARTMENT_ID" \
      --display-name "$DISPLAY_NAME" --lifecycle-state RUNNING \
      --query 'data[0].id' --raw-output 2>/dev/null)
    if [ -n "$EX" ] && [ "$EX" != "None" ]; then
      echo "已存在实例 $EX"; send_notify "ARM实例已存在" "ID: $EX"; exit 0
    fi
    echo "  配额已满，本轮停止。"; break
  elif echo "$RESULT" | grep -qiE "TooManyRequests|rate limit|Throttling"; then
    THROTTLE_STREAK=$((THROTTLE_STREAK + 1))
    echo "  被限速，退避拉大间隔 (${INTERVAL}s -> $((INTERVAL + 30 > MAX_INTERVAL ? MAX_INTERVAL : INTERVAL + 30))s)...（连续第 ${THROTTLE_STREAK}/${MAX_THROTTLE_STREAK} 次）"
    [ "$ADAPTIVE" = "true" ] && INTERVAL=$((INTERVAL + 30 > MAX_INTERVAL ? MAX_INTERVAL : INTERVAL + 30))
    if [ "$THROTTLE_STREAK" -ge "$MAX_THROTTLE_STREAK" ]; then
      echo "  连续 ${MAX_THROTTLE_STREAK} 次被限流，OCI 正在压我们的速率，提前收工等下一轮。"
      break
    fi
    sleep "$INTERVAL"
    continue
  elif echo "$RESULT" | grep -qi "provisioning"; then
    ID=$(echo "$RESULT" | grep -oP '"id":\s*"ocid1\.instance[^"]*"' | head -1 | grep -oP 'ocid1\.instance[^"]*')
    # 公网 IP 分配需要时间，轮询等待（最多约 60s）
    IP=""
    for _w in 1 2 3 4 5 6; do
      sleep 10
      IP=$(query_ip)
      [ -n "$IP" ] && [ "$IP" != "None" ] && break
    done
    echo "  [OK] 抢到了！ID=$ID IP=${IP:-获取中}"
    echo "arm_ip=$IP" >> "${GITHUB_OUTPUT:-/dev/null}"
    send_notify "[OK] ARM抢机成功" "区域: $TARGET_AD\n配置: $OCPUS OCPU/$MEMORY GB\nIP: ${IP:-查看控制台}\n登录: ssh -i oracle_arm_id_rsa ubuntu@${IP:-IP}"
    exit 0
  else
    echo "  未知返回:"; echo "$RESULT" | head -5
  fi
  [ "$i" -lt "$MAX_ATTEMPTS" ] && sleep "$INTERVAL"
done

ELAPSED=$(( $(date +%s) - START_TS ))
echo "本轮未抢到：实际尝试 $i/$MAX_ATTEMPTS 次，用时 ${ELAPSED}s，当前节奏 ${INTERVAL}s，下轮据此继续。"
exit 0
