# 使用官方 .NET 8 运行时镜像作为基础镜像
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS base

# 设置工作目录
WORKDIR /app

# 将构建好的发布文件复制到容器中
COPY ./publish/ ./

# 环境变量配置（用户名密码登录模式，可选）
ENV APP_USER=defaultuser \
    APP_PASSWORD=defaultpass

# 说明：支持两种登录模式
# 1. Session 模式：挂载 session.json 文件到 /app/session.json
#    docker run -v /path/to/session.json:/app/session.json your-image
# 2. 用户名密码模式：设置环境变量 APP_USER 和 APP_PASSWORD

# 启动程序
ENTRYPOINT ["dotnet", "CtYun.dll"]
