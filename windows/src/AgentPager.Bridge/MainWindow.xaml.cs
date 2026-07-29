using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;
using AgentPager.Core;
using QRCoder;

namespace AgentPager.Bridge;

public partial class MainWindow : Window
{
    private readonly BridgeRuntime _runtime;
    private bool _refreshing;

    public MainWindow(BridgeRuntime runtime)
    {
        _runtime = runtime;
        InitializeComponent();
        Refresh();
    }

    public event Action? HideRequested;

    public void Refresh()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.Invoke(Refresh);
            return;
        }
        _refreshing = true;
        var state = _runtime.State;
        ServiceStatusText.Text = state.ServiceStatus;
        PhoneCountText.Text = state.PhoneCount.ToString();
        HookStatusText.Text = state.HookInstalled ? "已写入" : "未安装";
        LastHookText.Text = state.LastHookAt?.ToString("yyyy-MM-dd HH:mm:ss") ?? "尚未收到";
        PairingTextBox.Text = state.PairingText;
        PairingQrImage.Source = QrCode(state.PairingText);
        NetworkCombo.ItemsSource = state.Networks;
        NetworkCombo.SelectedValue = state.SelectedAddress;
        StartupCheckBox.IsChecked = _runtime.Settings.LaunchAtLogin;
        DiagnosticText.Text = state.LastError is null
            ? $"49361/49362 · {state.TaskCount} 个任务 · 数据目录 {AgentPagerPaths.DataRoot}"
            : state.LastError;
        DiagnosticText.Foreground = state.LastError is null
            ? (System.Windows.Media.Brush)FindResource("Muted")
            : System.Windows.Media.Brushes.OrangeRed;
        _refreshing = false;
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        e.Cancel = true;
        HideRequested?.Invoke();
    }

    private void InstallHook_Click(object sender, RoutedEventArgs e) => _runtime.InstallHook();
    private void UninstallHook_Click(object sender, RoutedEventArgs e) => _runtime.UninstallHook();
    private void RefreshNetworks_Click(object sender, RoutedEventArgs e) => _runtime.RefreshNetworks();

    private void NetworkCombo_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (!_refreshing && NetworkCombo.SelectedValue is string address)
            _runtime.SelectAddress(address);
    }

    private void StartupCheckBox_Changed(object sender, RoutedEventArgs e)
    {
        if (!_refreshing) _runtime.SetLaunchAtLogin(StartupCheckBox.IsChecked == true);
    }

    private void CopyPairing_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrEmpty(PairingTextBox.Text))
            System.Windows.Clipboard.SetText(PairingTextBox.Text);
    }

    private static BitmapImage QrCode(string text)
    {
        using var data = QRCodeGenerator.GenerateQrCode(text, QRCodeGenerator.ECCLevel.M);
        var bytes = new PngByteQRCode(data).GetGraphic(8);
        var image = new BitmapImage();
        using var memory = new MemoryStream(bytes);
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.StreamSource = memory;
        image.EndInit();
        image.Freeze();
        return image;
    }

    private void OpenLogs_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(AgentPagerPaths.LogsDirectory);
        Process.Start(new ProcessStartInfo("explorer.exe", AgentPagerPaths.LogsDirectory)
        {
            UseShellExecute = true,
        });
    }
}
