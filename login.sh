#!/bin/bash
# 天翼云AI电脑 Linux 命令行登录脚本
# 使用方法: ./login.sh <手机号> <密码> [deviceCode]

set -e

# 配置参数
USER_PHONE="${1:-}"
PASSWORD="${2:-}"
# 使用传入的 deviceCode，或使用浏览器中的固定值
DEVICE_CODE="${3:-web_sgrllN1zCxINVbWc5IZYqQK5dJk0q4qz}"
OCR_URL="https://orc.1999111.xyz/ocr"
MAX_RETRY=5

DEVICE_TYPE="60"
VERSION="103020001"
APP_MODEL="2"

if [ -z "$USER_PHONE" ] || [ -z "$PASSWORD" ]; then
    echo "用法: ./login.sh <手机号> <密码> [deviceCode]"
    echo "示例: ./login.sh 13980779568 yourpassword"
    echo "或使用自定义deviceCode: ./login.sh 13980779568 yourpassword web_xxxxx"
    exit 1
fi

# 计算 SHA256 密码
PASSWORD_HASH=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}')

echo "============================================"
echo "使用固定设备码: $DEVICE_CODE"
echo "版本: $VERSION (AI云电脑)"
echo "============================================"
echo ""

# 计算 MD5
compute_md5() {
    echo -n "$1" | md5sum | awk '{print $1}'
}

# 登录函数
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
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36" \
        -H "ctg-devicetype: $DEVICE_TYPE" \
        -H "ctg-version: $VERSION" \
        -H "ctg-devicecode: $DEVICE_CODE" \
        -H "ctg-appmodel: $APP_MODEL" \
        -H "referer: https://pc.ctyun.cn/" \
        -d "userAccount=$USER_PHONE" \
        -d "password=$PASSWORD_HASH" \
        -d "sha256Password=$PASSWORD_HASH" \
        -d "captchaCode=$CAPTCHA_CODE" \
        -d "deviceCode=$DEVICE_CODE" \
        -d "deviceName=Chrome浏览器" \
        -d "deviceType=$DEVICE_TYPE" \
        -d "deviceModel=Windows NT 10.0; Win64; x64" \
        -d "appVersion=3.2.0" \
        -d "sysVersion=Windows NT 10.0; Win64; x64" \
        -d "clientVersion=$VERSION")
    
    # 检查验证码错误
    if echo "$LOGIN_RESULT" | grep -q '"code":51030'; then
        echo "图形验证码错误，重试..."
        return 1
    fi
    
    # 检查是否登录成功
    if echo "$LOGIN_RESULT" | grep -q '"secretKey"'; then
        echo ""
        echo "✅ 登录成功！"
        
        # 检查设备绑定状态
        if echo "$LOGIN_RESULT" | grep -q '"bondedDevice":true'; then
            echo "✅ 设备已绑定"
        else
            echo "⚠️ 设备未绑定 (bondedDevice: false)"
        fi
        
        # 提取关键信息
        USER_ACCOUNT=$(echo "$LOGIN_RESULT" | grep -oP '"userAccount"\s*:\s*"\K[^"]+')
        USER_ID=$(echo "$LOGIN_RESULT" | grep -oP '"userId"\s*:\s*\K[0-9]+')
        TENANT_ID=$(echo "$LOGIN_RESULT" | grep -oP '"tenantId"\s*:\s*\K[0-9]+')
        SECRET_KEY=$(echo "$LOGIN_RESULT" | grep -oP '"secretKey"\s*:\s*"\K[^"]+')
        
        echo ""
        echo ">>> 测试获取设备列表..."
        
        # 计算签名
        TIMESTAMP=$(date +%s%3N)
        SIGN_STR="${DEVICE_TYPE}${TIMESTAMP}${TENANT_ID}${TIMESTAMP}${USER_ID}${VERSION}${SECRET_KEY}"
        SIGNATURE=$(compute_md5 "$SIGN_STR")
        SIGNATURE_UPPER=$(echo "$SIGNATURE" | tr 'a-z' 'A-Z')
        
        # 调用设备列表 API
        DEVICE_LIST=$(curl -s \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36" \
            -H "ctg-devicetype: $DEVICE_TYPE" \
            -H "ctg-version: $VERSION" \
            -H "ctg-devicecode: $DEVICE_CODE" \
            -H "ctg-appmodel: $APP_MODEL" \
            -H "ctg-userid: $USER_ID" \
            -H "ctg-tenantid: $TENANT_ID" \
            -H "ctg-timestamp: $TIMESTAMP" \
            -H "ctg-requestid: $TIMESTAMP" \
            -H "ctg-signaturestr: $SIGNATURE_UPPER" \
            -H "referer: https://pc.ctyun.cn/" \
            "https://desk.ctyun.cn:8810/api/desktop/client/list")
        
        echo "设备列表响应: $DEVICE_LIST"
        
        # 检查设备列表是否成功
        if echo "$DEVICE_LIST" | grep -q '"desktopId"'; then
            echo ""
            echo "✅ 获取设备列表成功！"
            
            DESKTOP_ID=$(echo "$DEVICE_LIST" | grep -oP '"desktopId"\s*:\s*"\K[^"]+' | head -1)
            echo "DesktopId: $DESKTOP_ID"
            
            cat > session.json << EOF
{
    "userAccount": "$USER_ACCOUNT",
    "userId": $USER_ID,
    "tenantId": $TENANT_ID,
    "secretKey": "$SECRET_KEY",
    "mobilephone": "$USER_PHONE",
    "deviceCode": "$DEVICE_CODE",
    "desktopId": "$DESKTOP_ID",
    "version": "$VERSION"
}
EOF
            echo "session.json 已生成"
        else
            echo ""
            echo "⚠️ 设备列表获取失败，尝试直接使用已知的 desktopId..."
            
            # 硬编码已知的 desktopId
            DESKTOP_ID="22130831"
            
            cat > session.json << EOF
{
    "userAccount": "$USER_ACCOUNT",
    "userId": $USER_ID,
    "tenantId": $TENANT_ID,
    "secretKey": "$SECRET_KEY",
    "mobilephone": "$USER_PHONE",
    "deviceCode": "$DEVICE_CODE",
    "desktopId": "$DESKTOP_ID",
    "version": "$VERSION"
}
EOF
            echo "session.json 已生成（使用固定 desktopId: $DESKTOP_ID）"
        fi
        
        return 0
    fi
    
    echo "登录失败: $LOGIN_RESULT"
    return 1
}

# 执行登录
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
