# 使用官方 .NET 8 运行时镜像作为基础镜像
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS base

# 设置工作目录
WORKDIR /app

# 将构建好的发布文件复制到容器中
COPY ./publish/ ./

# 使用说明：
# 挂载 session.json 文件到容器（包含 deviceCode、secretKey 等登录信息）
# docker run -v /path/to/session.json:/app/session.json your-image

# 启动程序
ENTRYPOINT ["dotnet", "CtYun.dll"]
