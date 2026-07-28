using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using AgentPager.Core;

namespace AgentPager.Bridge;

public sealed class HookTcpServer(Func<CodexHookPayload, Task> hookHandler, DailyFileLog log)
    : ICodexPermissionResolver, IAsyncDisposable
{
    private readonly ConcurrentDictionary<string, TcpClient> _pending = new(StringComparer.Ordinal);
    private TcpListener? _listener;
    private CancellationTokenSource? _cancellation;
    private Task? _acceptTask;

    public void Start()
    {
        _cancellation = new();
        _listener = new(IPAddress.Loopback, 49361);
        _listener.Start();
        _acceptTask = AcceptLoop(_cancellation.Token);
    }

    public bool Resolve(string sessionID, CodexPermissionDecision decision)
    {
        if (!_pending.TryRemove(sessionID, out var client)) return false;
        try
        {
            using (client)
            {
                var response = CodexHookOutput.Permission(decision);
                client.GetStream().Write(response);
            }
            return true;
        }
        catch (IOException) { return false; }
    }

    private async Task AcceptLoop(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                var client = await _listener!.AcceptTcpClientAsync(cancellationToken);
                _ = Handle(client, cancellationToken);
            }
            catch (OperationCanceledException) { break; }
            catch (SocketException error) { log.Write("ERROR", $"Hook accept: {error.Message}"); }
        }
    }

    private async Task Handle(TcpClient client, CancellationToken cancellationToken)
    {
        try
        {
            var stream = client.GetStream();
            using var reader = new StreamReader(stream, Encoding.UTF8, false, 4096, leaveOpen: true);
            var line = await reader.ReadLineAsync(cancellationToken);
            if (line is null) { client.Dispose(); return; }
            var hook = JsonSerializer.Deserialize<CodexHookPayload>(line, WireJson.Options);
            if (hook is null) { client.Dispose(); return; }

            if (hook.HookEventName == CodexHookEventName.PermissionRequest)
            {
                if (_pending.TryGetValue(hook.SessionID, out var previous)) previous.Dispose();
                _pending[hook.SessionID] = client;
                await hookHandler(hook);
                return;
            }

            await hookHandler(hook);
            await stream.WriteAsync("\n"u8.ToArray(), cancellationToken);
            client.Dispose();
        }
        catch (Exception error) when (error is IOException or JsonException or OperationCanceledException)
        {
            client.Dispose();
            log.Write("WARN", $"Hook 请求失败：{error.Message}");
        }
    }

    public async ValueTask DisposeAsync()
    {
        _cancellation?.Cancel();
        _listener?.Stop();
        foreach (var client in _pending.Values) client.Dispose();
        _pending.Clear();
        if (_acceptTask is not null)
            try { await _acceptTask; } catch (OperationCanceledException) { }
        _cancellation?.Dispose();
    }
}
