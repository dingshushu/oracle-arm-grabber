#!/bin/bash
# Oracle Free Tier ARM 抢机脚本 —— 供 GitHub Actions 调用
# 特性：
#   1) 自适应调速：被 API 限速(429/Throttling)时自动拉大间隔退避，避免触发风控封号；
#      正常缺货时保持紧凑节奏（5s），不浪费窗口。
#   2) 容量预检（Compute Capacity Report）：每轮先问 Oracle 当前 AD 是否有 A1 容量，
#      仅当明确报 OUT_OF_HOST_CAPACITY 且开启 STRICT_SKIP 才跳过本轮，
#      默认关闭严格跳过（只记录日志），避免误杀真实可用窗口。
set -u

export SUPPRESS_LABEL_WARNING=True
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
export OCI_CONFIG_FILE=$HOME/.oci/config

DISPLAY_NAME="arm"
OCPUS=2
MEMORY=12
BOOT_SIZE=100

MAX_ATTEMPTS="${MAX_ATTEMPTS:-10}"   # 单轮最多尝试次数
INTERVAL=8                          # 当前尝试间隔（秒），自适应调整
MIN_INTERVAL=5
MAX_INTERVAL=120                    # 退避上限

ADAPTIVE="${ADAPTIVE:-true}"            # 自适应调速开关
CAPACITY_PRECHECK="${CAPACITY_PRECHECK:-true}"  # 容量预检开关
STRICT_SKIP="${STRICT_SKIP:-false}"     # 仅在明确无容量时跳过（默认关，避免误杀）

SSH_FILE=$HOME/id_rsa.pub
printf '%s\n' "${SSH_KEY_PUB:-}" > "$SSH_FILE"
chmod 600 "$SSH_FILE"

send_notify() {
  if [ -n "${SCT_KEY:-}" ]; then
    curl -s -X POST "https://sctapi.ftqq.com/${SCT_KEY}.send" \
      --data-urlencode "title=$1" --data-urlencode "desp=$2" >/dev/null 2>&1
  fi
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
cap_status() {
  [ "$CAPACITY_PRECHECK" = "true" ] || { echo "DISABLED"; return; }
  AVAILABILITY_DOMAIN="$AVAILABILITY_DOMAIN" COMPARTMENT_ID="$COMPARTMENT_ID" \
  python3 - <<'PY'
import sys, os, oci
try:
    cfg = oci.config.from_file()
    core = oci.core.ComputeClient(cfg)
    sa = oci.core.models.CreateCapacityReportShapeAvailabilityDetails(
        instance_shape="VM.Standard.A1.Flex")
    details = oci.core.models.CreateComputeCapacityReportDetails(
        compartment_id=os.environ["COMPARTMENT_ID"],
        availability_domain=os.environ["AVAILABILITY_DOMAIN"],
        shape_availabilities=[sa])
    rep = core.create_compute_capacity_report(create_compute_capacity_report_details=details)
    # 完整打印返回结构，便于核对字段名（不同 SDK 版本可能不同）
    sys.stderr.write("CAP_DATA: %r\n" % (rep.data,))
    sas = getattr(rep.data, "shape_availabilities", None)
    if sas:
        sa0 = sas[0]
        st = getattr(sa0, "availability_status", None)
        sys.stderr.write("CAP_ST: %r\n" % (st,))
        print(st if st else "UNKNOWN")
    else:
        sys.stderr.write("CAP_NO_SHAPE_AVAIL\n")
        print("UNKNOWN")
except Exception as e:
    sys.stderr.write("CAP_ERR %s: %s\n" % (type(e).__name__, str(e)[:500]))
    print("UNKNOWN")
PY
}

CAP=$(cap_status)
echo "== 容量预检状态: ${CAP:-UNKNOWN} =="
if [ "$STRICT_SKIP" = "true" ] && [ "$CAP" = "OUT_OF_HOST_CAPACITY" ]; then
  echo "明确无容量且严格模式开启，跳过本轮以省调用。"
  exit 0
fi
# 优化：预检结果驱动本轮策略
if [ "$CAP" = "AVAILABLE" ]; then
  MAX_ATTEMPTS=$((MAX_ATTEMPTS + 5))
  echo "预检显示有容量，本轮加量到 $MAX_ATTEMPTS 次尝试。"
elif [ "$CAP" = "OUT_OF_HOST_CAPACITY" ]; then
  MAX_ATTEMPTS=$((MAX_ATTEMPTS / 2))
  echo "预检显示无容量（非严格模式仍尝试），本轮减到 $MAX_ATTEMPTS 次省调用。"
fi

i=0
while [ "$i" -lt "$MAX_ATTEMPTS" ]; do
  i=$((i+1))
  TS=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$TS] 第 $i/$MAX_ATTEMPTS 次尝试（间隔 ${INTERVAL}s）..."

  RESULT=$(oci --no-retry compute instance launch --output json \
    --availability-domain "$AVAILABILITY_DOMAIN" \
    --compartment-id "$COMPARTMENT_ID" \
    --shape "VM.Standard.A1.Flex" \
    --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY}" \
    --display-name "$DISPLAY_NAME" \
    --image-id "$IMAGE_ID" \
    --boot-volume-size-in-gbs "$BOOT_SIZE" \
    --subnet-id "$SUBNET_ID" \
    --assign-public-ip true \
    --ssh-authorized-keys-file "$SSH_FILE" 2>&1)

  if echo "$RESULT" | grep -qiE "Out of host capacity|Out of capacity"; then
    echo "  没货，保持紧凑节奏。"
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
    echo "  被限速，退避拉大间隔 (${INTERVAL}s -> $((INTERVAL + 30 > MAX_INTERVAL ? MAX_INTERVAL : INTERVAL + 30))s)..."
    [ "$ADAPTIVE" = "true" ] && INTERVAL=$((INTERVAL + 30 > MAX_INTERVAL ? MAX_INTERVAL : INTERVAL + 30))
    sleep "$INTERVAL"
    continue
  elif echo "$RESULT" | grep -qi "provisioning"; then
    ID=$(echo "$RESULT" | grep -oP '"id":\s*"ocid1\.instance[^"]*"' | head -1 | grep -oP 'ocid1\.instance[^"]*')
    sleep 10
    IP=$(oci --no-retry compute instance list --compartment-id "$COMPARTMENT_ID" \
      --display-name "$DISPLAY_NAME" --query 'data[0]."primary-public-ip"' \
      --raw-output 2>/dev/null)
    echo "  [OK] 抢到了！ID=$ID IP=$IP"
    echo "arm_ip=$IP" >> "${GITHUB_OUTPUT:-/dev/null}"
    send_notify "[OK] ARM抢机成功" "区域: $AVAILABILITY_DOMAIN\n配置: $OCPUS OCPU/$MEMORY GB\nIP: ${IP:-查看控制台}\n登录: ssh -i oracle_arm_id_rsa ubuntu@${IP:-IP}"
    exit 0
  else
    echo "  未知返回:"; echo "$RESULT" | head -5
  fi
  [ "$i" -lt "$MAX_ATTEMPTS" ] && sleep "$INTERVAL"
done

echo "本轮未抢到，等待下次调度（当前节奏 ${INTERVAL}s，下轮据此继续）。"
exit 0
