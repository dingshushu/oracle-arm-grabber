#!/bin/bash
# Oracle Free Tier ARM 抢机脚本 —— 供 GitHub Actions 调用
# 每轮调度内尝试若干次；抢到即发 Server酱 通知并退出。
set -u

export SUPPRESS_LABEL_WARNING=True
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
export OCI_CONFIG_FILE=$HOME/.oci/config

DISPLAY_NAME="arm"
OCPUS=2
MEMORY=12
BOOT_SIZE=100
ATTEMPTS=6
ATTEMPT_SLEEP=20

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

for i in $(seq 1 "$ATTEMPTS"); do
  TS=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$TS] 第 $i/$ATTEMPTS 次尝试..."
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
    echo "  没货，继续..."
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
  elif echo "$RESULT" | grep -qiE "TooManyRequests|rate limit"; then
    echo "  被限速，稍等..."; sleep 30
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
  [ "$i" -lt "$ATTEMPTS" ] && sleep "$ATTEMPT_SLEEP"
done

echo "本轮未抢到，等待下次调度。"
exit 0
