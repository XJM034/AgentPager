using System.Collections.Concurrent;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace AgentPager.Bridge;

public sealed class LanBridgeServer(
    Func<string> pairingProvider,
    Func<string> snapshotProvider,
    Func<string, Task> messageHandler,
    Action<int> countChanged,
    DailyFileLog log) : IAsyncDisposable
{
    private sealed class Client(WebSocket socket) : IAsyncDisposable
    {
        private readonly SemaphoreSlim _sendLock = new(1, 1);
        public WebSocket Socket { get; } = socket;

        public async Task Send(string text, CancellationToken cancellationToken = default)
        {
            await _sendLock.WaitAsync(cancellationToken);
            try
            {
                if (Socket.State == WebSocketState.Open)
                    await Socket.SendAsync(Encoding.UTF8.GetBytes(text), WebSocketMessageType.Text, true, cancellationToken);
            }
            finally { _sendLock.Release(); }
        }

        public async ValueTask DisposeAsync()
        {
            if (Socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
                try { await Socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Bridge shutdown", CancellationToken.None); }
                catch (WebSocketException) { }
            Socket.Dispose();
            _sendLock.Dispose();
        }
    }

    private readonly ConcurrentDictionary<Guid, Client> _clients = [];
    private WebApplication? _application;

    public int ClientCount => _clients.Count;

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        var options = new WebApplicationOptions { Args = [], ApplicationName = typeof(LanBridgeServer).Assembly.FullName };
        var builder = WebApplication.CreateSlimBuilder(options);
        builder.Logging.ClearProviders();
        builder.WebHost.UseUrls("http://0.0.0.0:49362");
        builder.Services.AddRouting();
        var app = builder.Build();
        app.UseWebSockets(new WebSocketOptions { KeepAliveInterval = TimeSpan.FromSeconds(20) });

        app.MapGet("/pairing", async context =>
        {
            if (context.Connection.RemoteIpAddress is null ||
                !IPAddress.IsLoopback(context.Connection.RemoteIpAddress))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                return;
            }
            context.Response.ContentType = "application/json; charset=utf-8";
            await context.Response.WriteAsync(pairingProvider());
        });

        app.Map("/agentgrid", HandleWebSocket);
        await app.StartAsync(cancellationToken);
        _application = app;
    }

    public async Task BroadcastAsync(string text)
    {
        foreach (var pair in _clients.ToList())
        {
            try { await pair.Value.Send(text); }
            catch (Exception error) when (error is WebSocketException or OperationCanceledException)
            {
                await Remove(pair.Key);
            }
        }
    }

    private async Task HandleWebSocket(HttpContext context)
    {
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }
        var socket = await context.WebSockets.AcceptWebSocketAsync();
        var id = Guid.NewGuid();
        var client = new Client(socket);
        _clients[id] = client;
        countChanged(_clients.Count);
        try
        {
            await client.Send(snapshotProvider(), context.RequestAborted);
            var buffer = new byte[64 * 1024];
            using var message = new MemoryStream();
            while (socket.State == WebSocketState.Open)
            {
                var result = await socket.ReceiveAsync(buffer, context.RequestAborted);
                if (result.MessageType == WebSocketMessageType.Close) break;
                if (result.MessageType != WebSocketMessageType.Text) continue;
                await message.WriteAsync(buffer.AsMemory(0, result.Count), context.RequestAborted);
                if (!result.EndOfMessage) continue;
                if (message.Length > 1024 * 1024) break;
                var text = Encoding.UTF8.GetString(message.ToArray());
                message.SetLength(0);
                await messageHandler(text);
            }
        }
        catch (Exception error) when (error is WebSocketException or OperationCanceledException or IOException)
        {
            log.Write("WARN", $"WebSocket 关闭：{error.Message}");
        }
        finally { await Remove(id); }
    }

    private async Task Remove(Guid id)
    {
        if (_clients.TryRemove(id, out var client))
        {
            await client.DisposeAsync();
            countChanged(_clients.Count);
        }
    }

    public async ValueTask DisposeAsync()
    {
        foreach (var id in _clients.Keys.ToList()) await Remove(id);
        if (_application is not null)
        {
            await _application.StopAsync();
            await _application.DisposeAsync();
        }
    }
}
