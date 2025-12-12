#!/bin/bash
# 天翼云电脑完整登录测试脚本
# 用于测试不同 API 调用顺序和参数

set -e

USER_PHONE="${1:-}"
PASSWORD="${2:-}"
OCR_URL="https://orc.1999111.xyz/ocr"

if [ -z "$USER_PHONE" ] || [ -z "$PASSWORD" ]; then
    echo "用法: ./test_api.sh <手机号> <密码>"
    exit 1
fi

DEVICE_CODE="web_$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
DEVICE_TYPE="60"
VERSION="1020700001"
PASSWORD_HASH=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}')

compute_md5() {
    echo -n "$1" | md5sum | awk '{print $1}'
}

echo "============================================"
echo "设备码: $DEVICE_CODE"
echo "============================================"

# 步骤1: 获取并识别验证码
echo ""
echo ">>> 步骤1: 获取验证码..."
for i in {1..5}; do
    CAPTCHA_URL="https://desk.ctyun.cn:8810/api/auth/client/captcha?height=36&width=85&userInfo=${USER_PHONE}&mode=auto&_t=$(date +%s%3N)"
    CAPTCHA_B64=$(curl -s "$CAPTCHA_URL" | base64 -w 0)
    
    OCR_RESULT=$(curl -s -X POST "$OCR_URL" -F "image=$CAPTCHA_B64")
    CAPTCHA_CODE=$(echo "$OCR_RESULT" | grep -oP '"data"\s*:\s*"\K[^"]+')
    echo "尝试 $i: 验证码=$CAPTCHA_CODE"
    
    # 步骤2: 登录
    echo ">>> 步骤2: 登录..."
    LOGIN_RESULT=$(curl -s -X POST "https://desk.ctyun.cn:8810/api/auth/client/login" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -H "ctg-devicetype: $DEVICE_TYPE" \
        -H "ctg-version: $VERSION" \
        -H "ctg-devicecode: $DEVICE_CODE" \
        -H "referer: https://pc.ctyun.cn/" \
        -d "userAccount=$USER_PHONE" \
        -d "password=$PASSWORD_HASH" \
        -d "sha256Password=$PASSWORD_HASH" \
        -d "captchaCode=$CAPTCHA_CODE" \
        -d "deviceCode=$DEVICE_CODE" \
        -d "deviceName=Chrome浏览器" \
        -d "deviceType=$DEVICE_TYPE" \
        -d "deviceModel=Windows NT 10.0; Win64; x64" \
        -d "appVersion=2.7.0" \
        -d "sysVersion=Windows NT 10.0; Win64; x64" \
        -d "clientVersion=$VERSION")
    
    # 如果验证码错误，重试
    if echo "$LOGIN_RESULT" | grep -q '"code":51030'; then
        echo "验证码错误，重试..."
        continue
    fi
    
    # 如果登录成功
    if echo "$LOGIN_RESULT" | grep -q '"secretKey"'; then
        echo "登录成功！"
        break
    fi
    
    echo "登录失败: $LOGIN_RESULT"
    exit 1
done

# 提取登录信息
USER_ID=$(echo "$LOGIN_RESULT" | grep -oP '"userId"\s*:\s*\K[0-9]+')
TENANT_ID=$(echo "$LOGIN_RESULT" | grep -oP '"tenantId"\s*:\s*\K[0-9]+')
SECRET_KEY=$(echo "$LOGIN_RESULT" | grep -oP '"secretKey"\s*:\s*"\K[^"]+')

echo ""
echo "UserId: $USER_ID"
echo "TenantId: $TENANT_ID"
echo "SecretKey: $SECRET_KEY"

# 步骤3: 立即获取设备列表（与 C# 代码完全一致的调用方式）
echo ""
echo ">>> 步骤3: 获取设备列表..."
TIMESTAMP=$(date +%s%3N)
SIGN_STR="${DEVICE_TYPE}${TIMESTAMP}${TENANT_ID}${TIMESTAMP}${USER_ID}${VERSION}${SECRET_KEY}"
SIGNATURE=$(compute_md5 "$SIGN_STR")

echo "Timestamp: $TIMESTAMP"
echo "SignatureStr: $SIGN_STR"
echo "Signature: $SIGNATURE"

DEVICE_LIST=$(curl -s \
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
    -H "ctg-devicetype: $DEVICE_TYPE" \
    -H "ctg-version: $VERSION" \
    -H "ctg-devicecode: $DEVICE_CODE" \
    -H "ctg-userid: $USER_ID" \
    -H "ctg-tenantid: $TENANT_ID" \
    -H "ctg-timestamp: $TIMESTAMP" \
    -H "ctg-requestid: $TIMESTAMP" \
    -H "ctg-signaturestr: $SIGNATURE" \
    -H "referer: https://pc.ctyun.cn/" \
    "https://desk.ctyun.cn:8810/api/desktop/client/list")

echo ""
echo "设备列表响应: $DEVICE_LIST"
