#!/bin/bash
# 天翼云电脑 Linux 命令行登录脚本
# 使用方法: ./login.sh <手机号> <密码>

set -e

# 配置参数
USER_PHONE="${1:-}"
PASSWORD="${2:-}"
OCR_URL="https://orc.1999111.xyz/ocr"  # 验证码识别服务
MAX_RETRY=5  # 最大重试次数

if [ -z "$USER_PHONE" ] || [ -z "$PASSWORD" ]; then
    echo "用法: ./login.sh <手机号> <密码>"
    exit 1
fi

# 生成随机设备码
DEVICE_CODE="web_$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"
DEVICE_TYPE="60"
VERSION="1020700001"

# 计算 SHA256 密码
PASSWORD_HASH=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}')

echo "设备码: $DEVICE_CODE"
echo "密码哈希: $PASSWORD_HASH"
echo ""

# 登录函数（带重试）
attempt_login() {
    local attempt=$1
    echo "========== 尝试第 $attempt 次 =========="
    
    # 步骤1: 获取图片验证码
    echo ">>> 获取验证码..."
    CAPTCHA_URL="https://desk.ctyun.cn:8810/api/auth/client/captcha?height=36&width=85&userInfo=${USER_PHONE}&mode=auto&_t=$(date +%s%3N)"
    CAPTCHA_B64=$(curl -s "$CAPTCHA_URL" | base64 -w 0)
    
    # 步骤2: 识别验证码
    echo ">>> 识别验证码..."
    OCR_RESULT=$(curl -s -X POST "$OCR_URL" -F "image=$CAPTCHA_B64")
    CAPTCHA_CODE=$(echo "$OCR_RESULT" | grep -oP '"data"\s*:\s*"\K[^"]+')
    echo "验证码: $CAPTCHA_CODE"
    
    if [ -z "$CAPTCHA_CODE" ]; then
        echo "验证码识别失败，重试..."
        return 1
    fi
    
    # 步骤3: 登录
    echo ">>> 登录中..."
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
    
    # 检查验证码错误（需要重试）
    if echo "$LOGIN_RESULT" | grep -q '"code":51030'; then
        echo "图形验证码错误，重试..."
        return 1
    fi
    
    # 检查是否需要手机验证码
    if echo "$LOGIN_RESULT" | grep -q '"needSmsValidate"\s*:\s*true'; then
        echo ""
        echo "⚠️  需要手机验证码，此脚本无法继续"
        exit 1
    fi
    
    # 检查是否登录成功
    if echo "$LOGIN_RESULT" | grep -q '"secretKey"'; then
        echo ""
        echo "✅ 登录成功！"
        
        # 提取关键信息并保存到 session.json
        USER_ACCOUNT=$(echo "$LOGIN_RESULT" | grep -oP '"userAccount"\s*:\s*"\K[^"]+')
        USER_ID=$(echo "$LOGIN_RESULT" | grep -oP '"userId"\s*:\s*\K[0-9]+')
        TENANT_ID=$(echo "$LOGIN_RESULT" | grep -oP '"tenantId"\s*:\s*\K[0-9]+')
        SECRET_KEY=$(echo "$LOGIN_RESULT" | grep -oP '"secretKey"\s*:\s*"\K[^"]+')
        
        cat > session.json << EOF
{
    "userAccount": "$USER_ACCOUNT",
    "userId": $USER_ID,
    "tenantId": $TENANT_ID,
    "secretKey": "$SECRET_KEY",
    "mobilephone": "$USER_PHONE",
    "deviceCode": "$DEVICE_CODE"
}
EOF
        
        echo "session.json 已生成:"
        cat session.json
        return 0
    fi
    
    # 其他错误
    echo "登录失败: $LOGIN_RESULT"
    return 1
}

# 执行登录（自动重试）
for i in $(seq 1 $MAX_RETRY); do
    if attempt_login $i; then
        exit 0
    fi
    echo ""
    sleep 1
done

echo ""
echo "❌ 登录失败，已重试 $MAX_RETRY 次"
exit 1
