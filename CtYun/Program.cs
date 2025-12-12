using CtYun;
using System.Net.WebSockets;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;


Console.WriteLine($"v {Assembly.GetEntryAssembly().GetName().Version}");
var connectText = "";

var t = new LoginInfo()
{
    DeviceType = "60",
    DeviceCode = "",  // 将从 session.json 读取
    Version = "103020001"
};

// 检查是否存在 session.json 文件（Session 登录模式）
bool useSessionLogin = File.Exists("session.json");
if (useSessionLogin)
{
    Console.WriteLine("检测到 session.json，使用 Session 登录模式...");
    try
    {
        var sessionJson = File.ReadAllText("session.json");
        var sessionDoc = JsonDocument.Parse(sessionJson);
        var root = sessionDoc.RootElement;
        
        // 从 session.json 读取登录态信息
        if (root.TryGetProperty("userAccount", out var userAccountEl))
            t.UserAccount = userAccountEl.GetString();
        if (root.TryGetProperty("userId", out var userIdEl))
            t.UserId = userIdEl.GetInt32();
        if (root.TryGetProperty("tenantId", out var tenantIdEl))
            t.TenantId = tenantIdEl.GetInt32();
        if (root.TryGetProperty("secretKey", out var secretKeyEl))
            t.SecretKey = secretKeyEl.GetString();
        if (root.TryGetProperty("mobilephone", out var mobilePhoneEl))
            t.UserPhone = mobilePhoneEl.GetString();
        // 关键：使用登录时的 deviceCode，保持一致性
        if (root.TryGetProperty("deviceCode", out var deviceCodeEl))
            t.DeviceCode = deviceCodeEl.GetString();
            
        Console.WriteLine($"Session 登录成功: userId={t.UserId}, tenantId={t.TenantId}, deviceCode={t.DeviceCode}");
    }
    catch (Exception ex)
    {
        Console.WriteLine("session.json 解析错误: " + ex.Message);
        return;
    }
}

if (File.Exists("connect.txt") && Environment.GetEnvironmentVariable("LOAD_CACHE") == "1")
{
    connectText = File.ReadAllText("connect.txt");
}

if (string.IsNullOrEmpty(connectText) || connectText.IndexOf("\"desktopInfo\":null") != -1)
{
    if (useSessionLogin)
    {
        // Session 模式：跳过登录，直接获取设备列表
        Console.WriteLine("使用 Session 获取设备列表...");
        var cyApi = new CtYunApi(t);
        t.DesktopId = await cyApi.GetLlientListAsync();
        if (string.IsNullOrEmpty(t.DesktopId))
        {
            Console.WriteLine("获取设备列表失败，请检查 session.json 是否过期。");
            return;
        }
        connectText = await cyApi.ConnectAsync();
        File.WriteAllText("connect.txt", connectText);
    }
    else if (IsRunningInContainer())
    {
        // Docker/Linux 环境：使用环境变量
        t.UserPhone = Environment.GetEnvironmentVariable("APP_USER");
        t.Password = ComputeSha256Hash(Environment.GetEnvironmentVariable("APP_PASSWORD"));
        if (string.IsNullOrEmpty(t.UserPhone) || string.IsNullOrEmpty(t.Password))
        {
            Console.WriteLine("错误：必须设置环境变量 APP_USER 和 APP_PASSWORD");
            return;
        }
        // 重试三次
        for (int i = 0; i < 3; i++)
        {
            var cyApi = new CtYunApi(t);
            if (!await cyApi.LoginAsync())
            {
                Console.Write($"重试第{i + 1}次。");
                continue;
            }
            t.DesktopId = await cyApi.GetLlientListAsync();
            connectText = await cyApi.ConnectAsync();
            File.WriteAllText("connect.txt", connectText);
            break;
        }
    }
    else
    {
        // Windows 环境：交互式输入
        Console.Write("请输入账号：");
        t.UserPhone = Console.ReadLine();

        Console.Write("请输入密码：");
        t.Password = ComputeSha256Hash(ReadPassword()); // 隐藏密码输入
        
        // 重试三次
        for (int i = 0; i < 3; i++)
        {
            var cyApi = new CtYunApi(t);
            if (!await cyApi.LoginAsync())
            {
                Console.Write($"重试第{i + 1}次。");
                continue;
            }
            t.DesktopId = await cyApi.GetLlientListAsync();
            connectText = await cyApi.ConnectAsync();
            File.WriteAllText("connect.txt", connectText);
            break;
        }
    }
    
    if (string.IsNullOrEmpty(connectText) || connectText.IndexOf("\"desktopInfo\":null") != -1)
    {
        Console.WriteLine("登录异常..connectText获取错误，检查电脑是否开机。");
        return;
    }
}
Console.WriteLine("connect信息：" + connectText);
byte[] message=null;
var wssHost = "";
try
{
    var connectJson = JsonSerializer.Deserialize(connectText, AppJsonSerializerContext.Default.ConnectInfo);
    var connectMessage = new ConnecMessage
    {
        type = 1,
        ssl = 1,
        host = connectJson.data.desktopInfo.clinkLvsOutHost.Split(":")[0],
        port = connectJson.data.desktopInfo.clinkLvsOutHost.Split(":")[1],
        ca = connectJson.data.desktopInfo.caCert,
        cert = connectJson.data.desktopInfo.clientCert,
        key = connectJson.data.desktopInfo.clientKey,
        servername = $"{connectJson.data.desktopInfo.host}:{connectJson.data.desktopInfo.port}"
    };
    t.DesktopId= connectJson.data.desktopInfo.desktopId.ToString();
    wssHost = connectJson.data.desktopInfo.clinkLvsOutHost;
    message = JsonSerializer.SerializeToUtf8Bytes(connectMessage, AppJsonSerializerContext.Default.ConnecMessage);

}
catch (Exception ex)
{
    Console.WriteLine("connect数据校验错误"+ ex.Message);
    return;
}
Console.WriteLine("日志如果显示[发送保活消息成功。]才算成功。");
while (true)
{
    var uri = new Uri($"wss://{wssHost}/clinkProxy/{t.DesktopId}/MAIN");
    using var client = new ClientWebSocket();
    // 添加 Header
    client.Options.SetRequestHeader("Origin", "https://pc.ctyun.cn");
    client.Options.SetRequestHeader("Pragma", "no-cache");
    client.Options.SetRequestHeader("Cache-Control", "no-cache");
    client.Options.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36");
    client.Options.AddSubProtocol("binary"); // 与 Sec-WebSocket-Protocol 对应
    try
    {
        Console.WriteLine("连接服务器中...");
        await client.ConnectAsync(uri, CancellationToken.None);
        Console.WriteLine("连接成功!");
        //接收消息
        _ = Task.Run(() => ReceiveMessagesAsync(client, CancellationToken.None));

        Console.WriteLine("发送连接信息.");
        await client.SendAsync(message, WebSocketMessageType.Text, true, CancellationToken.None);
        

        await Task.Delay(500);
        await client.SendAsync(Convert.FromBase64String("UkVEUQIAAAACAAAAGgAAAAAAAAABAAEAAAABAAAAEgAAAAkAAAAECAAA"), WebSocketMessageType.Binary, true, CancellationToken.None);

        await Task.Delay(TimeSpan.FromMinutes(1));
        Console.WriteLine("准备关闭连接重新发送保活信息.");
        await client.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", CancellationToken.None);
    }
    catch (Exception ex)
    {
        Console.WriteLine("WebSocket error: " + ex.Message);
    }
    async Task ReceiveMessagesAsync(ClientWebSocket ws, CancellationToken token)
    {
        var recvBuffer = new byte[4096];

        try
        {
            while (ws.State == WebSocketState.Open)
            {
                var result = await ws.ReceiveAsync(new ArraySegment<byte>(recvBuffer), token);
                if (result.MessageType == WebSocketMessageType.Close)
                {
                    Console.WriteLine("服务器关闭..");
                    await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", token);
                    break;
                }
                else
                {
                    byte[] extracted = new byte[result.Count];
                    Buffer.BlockCopy(recvBuffer, 0, extracted, 0, result.Count);
                    var hex = BitConverter.ToString(extracted).Replace("-", "");
                    if (hex.StartsWith("5245445102", StringComparison.OrdinalIgnoreCase))
                    {
                        Console.WriteLine("收到保活校验消息: " + hex);
                        var e = new Encryption();
                        var data = e.Execute(extracted);
                        Console.WriteLine("发送保活消息.");
                        await client.SendAsync(data, WebSocketMessageType.Binary, true, CancellationToken.None);
                        Console.WriteLine("发送保活消息成功。");
                    }
                    else {
                        if (hex.IndexOf("00000000") ==-1)
                        {
                            Console.WriteLine("收到消息: " + hex.Replace("000000000000", ""));
                        }
                    }

                    


                }
            }
        }
        catch (Exception ex)
        {
           

        }
    }


}

 static string ReadPassword()
{
    var password = new StringWriter();
    ConsoleKeyInfo key;

    do
    {
        key = Console.ReadKey(true);

        if (key.Key != ConsoleKey.Enter && key.Key != ConsoleKey.Backspace)
        {
            password.Write(key.KeyChar);
            Console.Write("*");
        }
        else if (key.Key == ConsoleKey.Backspace && password.ToString().Length > 0)
        {
            password.GetStringBuilder().Remove(password.ToString().Length - 1, 1);
            Console.Write("\b \b"); // 删除一个字符
        }
    } while (key.Key != ConsoleKey.Enter);

    Console.WriteLine();
    return password.ToString();
}

// 判断是否运行在容器中（Linux）
static bool IsRunningInContainer()
{
    // 简单判断是否存在 /.dockerenv 文件（适用于大多数 Docker 容器）
    return File.Exists("/.dockerenv");
}

string GenerateRandomString(int length)
{
    string chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    RandomNumberGenerator rng = RandomNumberGenerator.Create();
    var data = new byte[length];
    rng.GetBytes(data);

    var result = new char[length];
    for (int i = 0; i < length; i++)
    {
        result[i] = chars[data[i] % chars.Length];
    }

    return new string(result);
}
static string ComputeSha256Hash(string rawData)
{
    var bytes = Encoding.UTF8.GetBytes(rawData);
    // 创建 SHA256 实例
    using (var sha256 = SHA256.Create())
    {
        byte[] hash = sha256.ComputeHash(bytes);
        return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
    }
}

//ws登录的相关会把已登录t掉线
//var sendLoginInfo = new SendLoginInfo
//{
//    Type = 112,
//    Size = t.BufferSize()
//};
//sendLoginInfo.Data = new byte[sendLoginInfo.Size];
//t.ToBuffer(sendLoginInfo.Data);

//var by=new byte[sendLoginInfo.BufferSize()];
//sendLoginInfo.ToBuffer(by);
//string hex = BitConverter.ToString(by).Replace("-", " ");