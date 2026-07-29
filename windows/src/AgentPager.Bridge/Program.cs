using System.Diagnostics;
using System.IO.Pipes;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Windows;
using AgentPager.Core;

namespace AgentPager.Bridge;

public static class Program
{
    private const string MutexName = "Local\\AgentPager.Bridge.Singleton";

    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Contains("--hook", StringComparer.OrdinalIgnoreCase))
            return HookClient.RunAsync().GetAwaiter().GetResult();
        if (args.Contains("--uninstall-hook", StringComparer.OrdinalIgnoreCase))
            return Maintenance.Uninstall();

        using var mutex = new Mutex(true, MutexName, out var created);
        if (!created)
        {
            SingleInstanceSignal.Send();
            return 0;
        }

        var app = new App(
            args.Contains("--first-run", StringComparer.OrdinalIgnoreCase),
            args.Contains("--background", StringComparer.OrdinalIgnoreCase));
        return app.Run();
    }
}

internal static class HookClient
{
    public static async Task<int> RunAsync()
    {
        try
        {
            using var input = Console.OpenStandardInput();
            using var memory = new MemoryStream();
            await input.CopyToAsync(memory);
            var payloadData = memory.ToArray();
            var payload = JsonSerializer.Deserialize<CodexHookPayload>(payloadData, WireJson.Options);
            if (payload is null) return 0;

            using var client = new TcpClient();
            using var connectTimeout = new CancellationTokenSource(TimeSpan.FromMilliseconds(400));
            await client.ConnectAsync("127.0.0.1", 49361, connectTimeout.Token);
            await using var stream = client.GetStream();
            await stream.WriteAsync(payloadData);
            await stream.WriteAsync("\n"u8.ToArray());
            await stream.FlushAsync();

            var wait = payload.HookEventName == CodexHookEventName.PermissionRequest
                ? TimeSpan.FromHours(1) : TimeSpan.FromSeconds(5);
            using var readTimeout = new CancellationTokenSource(wait);
            var response = new MemoryStream();
            var buffer = new byte[4096];
            while (true)
            {
                var count = await stream.ReadAsync(buffer, readTimeout.Token);
                if (count == 0) break;
                await response.WriteAsync(buffer.AsMemory(0, count), readTimeout.Token);
                if (buffer.AsSpan(0, count).Contains((byte)'\n')) break;
            }
            if (response.Length > 0)
            {
                response.Position = 0;
                await response.CopyToAsync(Console.OpenStandardOutput());
            }
        }
        catch (Exception error) when (error is IOException or SocketException or OperationCanceledException or JsonException)
        {
            // Hook 必须 fail-open，Bridge 不可用不能阻塞 Codex。
        }
        return 0;
    }
}

internal static class Maintenance
{
    public static int Uninstall()
    {
        try
        {
            _ = new CodexHookConfiguration().Uninstall();
            StartupRegistration.Disable();
            return 0;
        }
        catch { return 1; }
    }
}

internal static class SingleInstanceSignal
{
    private const string PipeName = "AgentPager.Bridge.Activate";

    public static void Send()
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            pipe.Connect(200);
            pipe.WriteByte(1);
        }
        catch (Exception error) when (error is IOException or TimeoutException) { }
    }

    public static async Task ListenAsync(Action activate, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await using var pipe = new NamedPipeServerStream(PipeName, PipeDirection.In, 1,
                    PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                await pipe.WaitForConnectionAsync(cancellationToken);
                _ = pipe.ReadByte();
                activate();
            }
            catch (OperationCanceledException) { break; }
            catch (IOException) { }
        }
    }
}

public sealed class App : System.Windows.Application
{
    private readonly bool _firstRun;
    private readonly bool _background;
    private BridgeRuntime? _runtime;
    private TrayController? _tray;
    private MainWindow? _window;
    private CancellationTokenSource? _cancellation;

    public App(bool firstRun, bool background)
    {
        _firstRun = firstRun;
        _background = background;
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
    }

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _cancellation = new();
        _runtime = new BridgeRuntime();
        _window = new MainWindow(_runtime);
        _tray = new TrayController(_runtime, ShowWindow, ExitApplication);
        if (!_background) _runtime.Settings.Save();
        _runtime.StateChanged += () => Dispatcher.Invoke(() =>
        {
            _window.Refresh();
            _tray.Refresh();
        });
        _window.HideRequested += () => _window.Hide();
        _ = SingleInstanceSignal.ListenAsync(() => Dispatcher.Invoke(ShowWindow), _cancellation.Token);
        await _runtime.StartAsync(_cancellation.Token);
        if (_firstRun || !_runtime.Settings.HasCompletedFirstRun)
        {
            _runtime.Settings.HasCompletedFirstRun = true;
            _runtime.Settings.Save();
        }
        if (!_background) ShowWindow();
    }

    private void ShowWindow()
    {
        if (_window is null) return;
        _window.Show();
        if (_window.WindowState == WindowState.Minimized) _window.WindowState = WindowState.Normal;
        _window.Activate();
    }

    private async void ExitApplication()
    {
        _cancellation?.Cancel();
        if (_runtime is not null) await _runtime.DisposeAsync();
        _tray?.Dispose();
        Shutdown();
    }
}
