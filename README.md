### windows用户直接下载Releases执行即可。

只需要登录一次即可，登录成功会保存缓存数据，

### docker使用指南

# 1. 运行登录脚本生成 session.json
./login.sh 手机号 密码

# 2. 使用生成的 session.json 运行 Docker
 docker run -d   --name ctyun   -v $(pwd)/session.json:/app/session.json wttwins/ctyun:latest

```
```
非必须参数，使用登录缓存。不写为不适应，1为使用
-e LOAD_CACHE ='1'
```

### 查看日志检查是否登录并连接成功。

```
docker logs -f ctyun

```


