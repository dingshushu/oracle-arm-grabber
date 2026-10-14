#!/bin/bash
# Oracle Free Tier AMD 抢机脚本 —— 供 GitHub Actions 调用
# 目标：Always Free 的 2 个 AMD 微实例（VM.Standard.E2.1.Micro，与 ARM 额度独立）
# 特性：
#   1) E2.1.Micro 容量通常充足：直接尝试 + 有限重试；被限速/没货时退避。
#   2) 动态发现最新的 Canonical Ubuntu x86_64 镜像（不硬编码 image id，区域换机不失效）。
#   3) 已存在（未终止）的实例自动跳过，不重复抢占免费额度。
#   4) 存储注意：Always Free 块存储总额 200GB（含启动卷）；ARM 启动卷 100GB，
#      故每个 AMD 启动卷 50GB，两台合计恰好用满。若第二台报块存储配额超限，
#      需把 ARM 脚本的 BOOT_SIZE 调小（ARM 实例尚未创建时调整无损失）。
set -u

export SUPPRESS_LABEL_WARNING=True
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
export OCI_CONFIG_FILE=$HOME/.oci/config

AMD_COUNT="${AMD_COUNT:-2}"          # 免费额度：2 个 E2.1.Micro
AMD_SHAPE="VM.Standard.E2.1.Micro"
AMD_BOOT_SIZE="${AMD_BOOT_SIZE:-50}" # GB（见文件头存储说明）
MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"    # 每个实例的尝试次数
INTERVAL=10                          # 重试间隔（秒）
BACKOFF=30                           # 被限速时的额外退避（秒）

SSH_FILE=$HOME/id_rsa.pub
printf '%s\n' "${SSH_KEY_PUB:-}" > "$SSH_FILE"
chmod 600 "$SSH_FILE"

send_notify() {
  if [ -n "${SCT_KEY:-}" ]; then
    curl -s -X POST "https://sctapi.ftqq.com/${SCT_KEY}.send" \
      --data-urlencode "title=$1" --data-urlencode "desp=$2" >/dev/null 2>&1
  fi
}

# 统计指定 display-name 的存活实例数（排除 TERMINATED；停止的实例仍占额度，算存活）
alive_count() {
  oci compute instance list --compartment-id "$COMPARTMENT_ID" \
    --display-name "$1" --output json 2>/dev/null \
    | python3 -c "import sys,json
try:
    d=json.load(sys.stdin).get('data',[])
    print(len([i for i in d if i.get('lifecycle-state')!='TERMINATED']))
except Exception:
    print(0)"
}

# 查询实例公网 IP（无存活实例/未分配时输出空）
# 注意：Instance 对象没有 primary-public-ip 字段，必须走
# vnic-attachment(拿 vnic-id) -> vnic get(拿 public-ip)，否则永远返回空。
query_ip() {
  local name="$1" iid vnic
  iid=$(oci compute instance list --compartment-id "$COMPARTMENT_ID" \
        --display-name "$name" --query 'data[0].id' --raw-output 2>/dev/null)
  [ -n "$iid" ] && [ "$iid" != "None" ] || return 0
  vnic=$(oci compute vnic-attachment list --compartment-id "$COMPARTMENT_ID" \
         --instance-id "$iid" --query 'data[0]."vnic-id"' --raw-output 2>/dev/null)
  [ -n "$vnic" ] && [ "$vnic" != "None" ] || return 0
  oci network vnic get --vnic-id "$vnic" --query 'data."public-ip"' --raw-output 2>/dev/null
}

# 动态发现最新的 Canonical Ubuntu x86_64 镜像（与 E2.1.Micro 兼容）
find_amd_image() {
  local img
  img=$(oci compute image list --compartment-id "$COMPARTMENT_ID" \
    --operating-system "Canonical Ubuntu" \
    --shape "$AMD_SHAPE" \
    --sort-by "TIMECREATED" --sort-order "DESC" \
    --query 'data[0].id' --raw-output 2>/dev/null)
  if [ -z "$img" ] || [ "$img" = "None" ]; then
    # 回退：不限操作系统名，仅按 shape 兼容性找最新可用镜像
    img=$(oci compute image list --compartment-id "$COMPARTMENT_ID" \
      --shape "$AMD_SHAPE" \
      --sort-by "TIMECREATED" --sort-order "DESC" \
      --query 'data[0].id' --raw-output 2>/dev/null)
  fi
  echo "$img"
}

echo "== AMD 抢机开始（目标 $AMD_COUNT x $AMD_SHAPE）=="
AMD_IMAGE=$(find_amd_image)
if [ -z "$AMD_IMAGE" ] || [ "$AMD_IMAGE" = "None" ]; then
  echo "未找到 $AMD_SHAPE 兼容的镜像，退出。"
  send_notify "AMD抢机异常" "未找到 $AMD_SHAPE 兼容镜像"
  exit 1
fi
echo "使用镜像: $AMD_IMAGE"

NEW_LAUNCHED=0
for n in $(seq 1 "$AMD_COUNT"); do
  NAME="amd"
  [ "$n" -gt 1 ] && NAME="amd-$n"
  CNT=$(alive_count "$NAME")
  if [ "$CNT" -gt 0 ]; then
    echo "实例 $NAME 已存在（存活 $CNT 个），跳过。"
    continue
  fi
  echo "== 开始抢 $NAME =="
  i=0
  while [ "$i" -lt "$MAX_ATTEMPTS" ]; do
    i=$((i+1))
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $NAME 第 $i/$MAX_ATTEMPTS 次尝试..."
    RESULT=$(oci --no-retry compute instance launch --output json \
      --availability-domain "$AVAILABILITY_DOMAIN" \
      --compartment-id "$COMPARTMENT_ID" \
      --shape "$AMD_SHAPE" \
      --display-name "$NAME" \
      --image-id "$AMD_IMAGE" \
      --boot-volume-size-in-gbs "$AMD_BOOT_SIZE" \
      --subnet-id "$SUBNET_ID" \
      --assign-public-ip true \
      --ssh-authorized-keys-file "$SSH_FILE" 2>&1)

    if echo "$RESULT" | grep -qiE "Out of host capacity|Out of capacity"; then
      echo "  没货，${INTERVAL}s 后重试。"; sleep "$INTERVAL"
    elif echo "$RESULT" | grep -qiE "LimitExceeded"; then
      echo "  配额超限（免费额度可能已被其他实例占用），停止重试。"
      echo "  返回: $(echo "$RESULT" | head -3)"
      break
    elif echo "$RESULT" | grep -qiE "TooManyRequests|rate limit|Throttling"; then
      echo "  被限速，退避 $((INTERVAL + BACKOFF))s。"
      sleep $((INTERVAL + BACKOFF))
      continue
    elif echo "$RESULT" | grep -qi "provisioning"; then
      ID=$(echo "$RESULT" | grep -oP '"id":\s*"ocid1\.instance[^"]*"' | head -1 | grep -oP 'ocid1\.instance[^"]*')
      # 公网 IP 分配需要时间，轮询等待（最多约 60s）
      IP=""
      for _w in 1 2 3 4 5 6; do
        sleep 10
        IP=$(query_ip "$NAME")
        [ -n "$IP" ] && [ "$IP" != "None" ] && break
      done
      echo "  [OK] $NAME 抢到！ID=$ID IP=${IP:-获取中}"
      NEW_LAUNCHED=$((NEW_LAUNCHED+1))
      break
    else
      echo "  未知返回:"; echo "$RESULT" | head -5
      sleep "$INTERVAL"
    fi
  done
done

# 汇总：输出所有存活 AMD 实例的公网 IP 到 GITHUB_OUTPUT（供 workflow 建 Issue）
for n in 1 2; do
  NAME="amd"; [ "$n" -gt 1 ] && NAME="amd-$n"
  IP=$(query_ip "$NAME")
  echo "  实例 $NAME 公网 IP: ${IP:-无}"
  if [ -n "$IP" ] && [ "$IP" != "None" ]; then
    if [ "$n" -eq 1 ]; then echo "amd_ip=$IP" >> "${GITHUB_OUTPUT:-/dev/null}"
    else echo "amd_ip_2=$IP" >> "${GITHUB_OUTPUT:-/dev/null}"; fi
  fi
done

# 汇总通知（仅在有新抢到时发，避免每轮轰炸）
if [ "$NEW_LAUNCHED" -gt 0 ]; then
  IP1=$(query_ip "amd"); IP2=$(query_ip "amd-2")
  send_notify "[OK] AMD抢机成功" "新抢到 $NEW_LAUNCHED 台 E2.1.Micro\nIP1: ${IP1:-获取中}\nIP2: ${IP2:-无}\n登录: ssh -i oracle_arm_id_rsa ubuntu@<IP>"
fi

echo "== AMD 抢机结束（本轮新抢 $NEW_LAUNCHED 台）=="
exit 0
