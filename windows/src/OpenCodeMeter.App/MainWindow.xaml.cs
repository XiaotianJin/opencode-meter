using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using OpenCodeMeter.App.Services;
using OpenCodeMeter.App.ViewModels;
using OpenCodeMeter.Core.Models;
using OpenCodeMeter.Core.Services;
using OpenCodeMeter.Core.Settings;

namespace OpenCodeMeter.App;

public partial class MainWindow : Window
{
    private const double BallWidth = 136;
    private const double BallHeight = 136;
    private const double CardWidth = 456;
    private const double CardHeight = 208;
    private const double StripWidth = 96;
    private const double StripHeight = 316;
    private const double SnapDistance = 28;

    private enum ViewState
    {
        Ball,
        Expanded,
        Docked,
    }

    private readonly MainViewModel _viewModel = new();
    private readonly UsageClient _client = new();
    private readonly DispatcherTimer _refreshTimer = new();
    private readonly DispatcherTimer _tickTimer = new();
    private readonly DispatcherTimer _hoverTimer = new();
    private readonly DispatcherTimer _collapseTimer = new();

    private readonly AppSettings _settings;
    private ViewState _state = ViewState.Ball;
    private DockEdge _dockEdge = DockEdge.None;
    private ContextMenu? _openMenu;
    private bool _loaded;
    private bool _isRefreshing;
    private bool _isDragging;
    private bool _dragArmed;
    private double _ballLeft;
    private double _ballTop;
    private double _dockLeft;
    private double _dockTop;
    private Point _dragStartCursor;
    private double _dragStartLeft;
    private double _dragStartTop;
    private DateTime _suppressHoverUntil;
    private int _animationToken;

    public MainWindow()
    {
        _settings = AppSettingsStore.Load();
        _viewModel.ApplySettings(_settings);

        InitializeComponent();
        DataContext = _viewModel;
        Topmost = _settings.AlwaysOnTop;

        RestoreInitialGeometry();
        BuildTimers();
    }

    private void BuildTimers()
    {
        _refreshTimer.Tick += async (_, _) => await RefreshAsync();

        _tickTimer.Interval = TimeSpan.FromSeconds(15);
        _tickTimer.Tick += (_, _) => _viewModel.Tick();

        _hoverTimer.Interval = TimeSpan.FromMilliseconds(220);
        _hoverTimer.Tick += (_, _) =>
        {
            _hoverTimer.Stop();
            TryExpand();
        };

        _collapseTimer.Interval = TimeSpan.FromMilliseconds(350);
        _collapseTimer.Tick += (_, _) =>
        {
            _collapseTimer.Stop();
            TryCollapse();
        };
    }

    private void RestoreInitialGeometry()
    {
        var work = SystemParameters.WorkArea;
        var defaultLeft = work.Right - BallWidth - 32;
        var defaultTop = work.Bottom - BallHeight - 48;

        _ballLeft = _settings.BallLeft ?? defaultLeft;
        _ballTop = _settings.BallTop ?? defaultTop;

        if (!MonitorService.IsVisible(new Point(_ballLeft + BallWidth / 2, _ballTop + BallHeight / 2)))
        {
            _ballLeft = defaultLeft;
            _ballTop = defaultTop;
        }

        if (_settings.Mode == WidgetMode.Docked && _settings.DockEdge != DockEdge.None)
        {
            _state = ViewState.Docked;
            _dockEdge = _settings.DockEdge;
            Width = StripWidth;
            Height = StripHeight;

            if (_settings.DockLeft is double savedLeft && _settings.DockTop is double savedTop)
            {
                // Restore the exact monitor as well; OnLoaded re-clamps against
                // that monitor's work area once the window handle exists.
                Left = savedLeft;
                Top = savedTop;
            }
            else
            {
                var top = _settings.DockTop ?? (_ballTop + BallHeight / 2 - StripHeight / 2);
                Left = _dockEdge == DockEdge.Left ? work.Left + 6 : work.Right - StripWidth - 6;
                Top = Math.Clamp(top, work.Top + 8, Math.Max(work.Top + 8, work.Bottom - StripHeight - 8));
            }

            _dockLeft = Left;
            _dockTop = Top;
        }
        else
        {
            _state = ViewState.Ball;
            Width = BallWidth;
            Height = BallHeight;
            Left = _ballLeft;
            Top = _ballTop;
        }

        UpdateVisualState(animate: false);
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        MonitorService.HideFromAltTab(this);
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _loaded = true;

        // The window handle exists now, so the monitor lookup is accurate even
        // when the last position was on a secondary display.
        ApplyState(_state, animate: false);

        _refreshTimer.Interval = TimeSpan.FromMinutes(_settings.RefreshMinutes);
        _refreshTimer.Start();
        _tickTimer.Start();

        Opacity = 0;
        BeginAnimation(
            OpacityProperty,
            new DoubleAnimation(1, TimeSpan.FromMilliseconds(220))
            {
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
            });

        _ = RefreshAsync();
    }

    private void OnClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        _refreshTimer.Stop();
        _tickTimer.Stop();
        _hoverTimer.Stop();
        _collapseTimer.Stop();
        SaveSettings();
        _client.Dispose();
    }

    // ------------------------------------------------------------------
    // data
    // ------------------------------------------------------------------

    private async Task RefreshAsync()
    {
        if (_isRefreshing) return;
        _isRefreshing = true;
        _viewModel.SetRefreshing(true);

        try
        {
            var service = OpenCodeServiceLocator.Discover()
                          ?? throw new UsageException(UsageError.ServiceMissing);
            var snapshot = await _client.FetchAsync(service);
            _viewModel.ApplySnapshot(snapshot, DateTimeOffset.Now);
        }
        catch (UsageException ex)
        {
            _viewModel.ApplyError(ex.Message);
        }
        catch (Exception ex)
        {
            _viewModel.ApplyError(ex.Message);
        }
        finally
        {
            _isRefreshing = false;
            _viewModel.SetRefreshing(false);
        }
    }

    private void SaveSettings()
    {
        _settings.BallLeft = _ballLeft;
        _settings.BallTop = _ballTop;
        _settings.Mode = _state == ViewState.Docked ? WidgetMode.Docked : WidgetMode.Ball;
        _settings.DockEdge = _state == ViewState.Docked ? _dockEdge : DockEdge.None;
        if (_state == ViewState.Docked)
        {
            _settings.DockLeft = _dockLeft;
            _settings.DockTop = _dockTop;
        }

        AppSettingsStore.Save(_settings);
    }

    // ------------------------------------------------------------------
    // layout / animation
    // ------------------------------------------------------------------

    private void ApplyState(ViewState target, bool animate)
    {
        var work = MonitorService.GetWorkArea(this);
        double left;
        double top;
        double width;
        double height;

        switch (target)
        {
            case ViewState.Ball:
                _dockEdge = DockEdge.None;
                width = BallWidth;
                height = BallHeight;
                left = _ballLeft;
                top = _ballTop;
                break;

            case ViewState.Expanded:
                width = CardWidth;
                height = CardHeight;
                left = _ballLeft + (BallWidth - CardWidth) / 2;
                top = _ballTop + (BallHeight - CardHeight) / 2;
                break;

            case ViewState.Docked:
            default:
                width = StripWidth;
                height = StripHeight;
                left = _dockEdge == DockEdge.Left ? work.Left + 6 : work.Right - width - 6;
                top = Top + Height / 2 - height / 2;
                break;
        }

        MonitorService.ClampTo(work, ref left, ref top, width, height);

        if (target == ViewState.Ball)
        {
            _ballLeft = left;
            _ballTop = top;
        }
        else if (target == ViewState.Docked)
        {
            _dockLeft = left;
            _dockTop = top;
            _settings.DockLeft = left;
            _settings.DockTop = top;
        }

        _state = target;
        SetGeometry(left, top, width, height, animate);
        UpdateVisualState(animate);

        // The expanded card is transient; only persist stable states.
        if (target != ViewState.Expanded)
        {
            SaveSettings();
        }
    }

    private void SetGeometry(double left, double top, double width, double height, bool animate)
    {
        if (!animate)
        {
            ClearGeometryAnimations();
            Left = left;
            Top = top;
            Width = width;
            Height = height;
            return;
        }

        var token = ++_animationToken;
        var duration = TimeSpan.FromMilliseconds(220);
        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };

        var leftAnimation = new DoubleAnimation(Left, left, duration) { EasingFunction = ease };
        var topAnimation = new DoubleAnimation(Top, top, duration) { EasingFunction = ease };
        var widthAnimation = new DoubleAnimation(Width, width, duration) { EasingFunction = ease };
        var heightAnimation = new DoubleAnimation(Height, height, duration) { EasingFunction = ease };

        heightAnimation.Completed += (_, _) =>
        {
            if (token != _animationToken) return;
            ClearGeometryAnimations();
            Left = left;
            Top = top;
            Width = width;
            Height = height;
        };

        BeginAnimation(LeftProperty, leftAnimation);
        BeginAnimation(TopProperty, topAnimation);
        BeginAnimation(WidthProperty, widthAnimation);
        BeginAnimation(HeightProperty, heightAnimation);
    }

    private void ClearGeometryAnimations()
    {
        _animationToken++;
        BeginAnimation(LeftProperty, null);
        BeginAnimation(TopProperty, null);
        BeginAnimation(WidthProperty, null);
        BeginAnimation(HeightProperty, null);
    }

    private void StopGeometryAnimation()
    {
        var left = Left;
        var top = Top;
        var width = Width;
        var height = Height;
        ClearGeometryAnimations();
        Left = left;
        Top = top;
        Width = width;
        Height = height;
    }

    private void UpdateVisualState(bool animate)
    {
        Fade(BallView, _state == ViewState.Ball ? 1 : 0, animate);
        Fade(WidgetView, _state == ViewState.Expanded ? 1 : 0, animate);
        Fade(StripView, _state == ViewState.Docked ? 1 : 0, animate);

        BallView.IsHitTestVisible = _state == ViewState.Ball;
        WidgetView.IsHitTestVisible = _state == ViewState.Expanded;
        StripView.IsHitTestVisible = _state == ViewState.Docked;
    }

    private static void Fade(UIElement element, double target, bool animate)
    {
        if (!animate)
        {
            element.BeginAnimation(OpacityProperty, null);
            element.Opacity = target;
            return;
        }

        element.BeginAnimation(
            OpacityProperty,
            new DoubleAnimation(target, TimeSpan.FromMilliseconds(150))
            {
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
            });
    }

    // ------------------------------------------------------------------
    // hover
    // ------------------------------------------------------------------

    private void OnMouseEnter(object sender, MouseEventArgs e)
    {
        if (!_loaded || _isDragging) return;
        _collapseTimer.Stop();
        if (_state == ViewState.Ball && DateTime.UtcNow >= _suppressHoverUntil)
        {
            _hoverTimer.Start();
        }
    }

    private void OnMouseLeave(object sender, MouseEventArgs e)
    {
        _hoverTimer.Stop();
        if (_state == ViewState.Expanded && !_isDragging)
        {
            _collapseTimer.Start();
        }
    }

    private void TryExpand()
    {
        if (_state != ViewState.Ball || _isDragging) return;
        if (!IsMouseOver) return;
        if (DateTime.UtcNow < _suppressHoverUntil) return;
        if (_openMenu?.IsOpen == true) return;

        _ballLeft = Left;
        _ballTop = Top;
        ApplyState(ViewState.Expanded, animate: true);
    }

    private void TryCollapse()
    {
        if (_state != ViewState.Expanded || _isDragging) return;
        if (IsMouseOver) return;
        if (_openMenu?.IsOpen == true) return;
        ApplyState(ViewState.Ball, animate: true);
    }

    // ------------------------------------------------------------------
    // dragging / docking
    // ------------------------------------------------------------------

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;

        if (e.ClickCount == 2)
        {
            OpenUsage();
            e.Handled = true;
            return;
        }

        // The expanded card is a read-only flyout; it collapses when the mouse
        // leaves instead of acting as a drag handle.
        if (_state == ViewState.Expanded) return;

        _hoverTimer.Stop();
        _collapseTimer.Stop();
        StopGeometryAnimation();

        _dragStartCursor = MonitorService.GetCursorPosition(this);
        _dragStartLeft = Left;
        _dragStartTop = Top;
        _dragArmed = true;
        _isDragging = false;
        CaptureMouse();
        e.Handled = true;
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        if (!_dragArmed) return;
        if (e.LeftButton != MouseButtonState.Pressed)
        {
            EndDrag();
            return;
        }

        var cursor = MonitorService.GetCursorPosition(this);
        var dx = cursor.X - _dragStartCursor.X;
        var dy = cursor.Y - _dragStartCursor.Y;

        if (!_isDragging)
        {
            if (Math.Abs(dx) < 4 && Math.Abs(dy) < 4) return;
            _isDragging = true;

            if (_state == ViewState.Docked)
            {
                // Pull the strip away from the edge and continue as a ball.
                _state = ViewState.Ball;
                _ballLeft = cursor.X - BallWidth / 2;
                _ballTop = cursor.Y - BallHeight / 2;
                Width = BallWidth;
                Height = BallHeight;
                Left = _ballLeft;
                Top = _ballTop;
                UpdateVisualState(animate: false);

                _dragStartCursor = cursor;
                _dragStartLeft = Left;
                _dragStartTop = Top;
                dx = 0;
                dy = 0;
            }

            Mouse.OverrideCursor = Cursors.SizeAll;
        }

        Left = _dragStartLeft + dx;
        Top = _dragStartTop + dy;
        e.Handled = true;
    }

    private void OnMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_dragArmed) return;
        EndDrag();
        e.Handled = true;
    }

    private void OnLostMouseCapture(object sender, MouseEventArgs e)
    {
        // EndDrag() releases the capture itself after clearing _dragArmed, so
        // this only handles an unexpected loss (Alt-Tab, another app grabbing
        // the mouse, etc.).
        if (!_dragArmed) return;

        _dragArmed = false;
        var wasDragging = _isDragging;
        _isDragging = false;
        Mouse.OverrideCursor = null;

        if (wasDragging)
        {
            FinishDrag();
            _suppressHoverUntil = DateTime.UtcNow.AddMilliseconds(420);
        }
    }

    private void EndDrag()
    {
        if (!_dragArmed) return;
        _dragArmed = false;
        if (IsMouseCaptured) ReleaseMouseCapture();
        Mouse.OverrideCursor = null;

        if (_isDragging)
        {
            _isDragging = false;
            FinishDrag();
        }

        _suppressHoverUntil = DateTime.UtcNow.AddMilliseconds(420);
    }

    private void FinishDrag()
    {
        var work = MonitorService.GetWorkArea(this);
        var dockLeft = Left - work.Left <= SnapDistance;
        var dockRight = work.Right - (Left + Width) <= SnapDistance;

        _ballLeft = Left;
        _ballTop = Top;

        if (dockLeft || dockRight)
        {
            _dockEdge = dockLeft ? DockEdge.Left : DockEdge.Right;
            ApplyState(ViewState.Docked, animate: true);
        }
        else
        {
            _dockEdge = DockEdge.None;
            ApplyState(ViewState.Ball, animate: true);
        }
    }

    // ------------------------------------------------------------------
    // menu / commands
    // ------------------------------------------------------------------

    private void OnMouseRightButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Right) return;

        _hoverTimer.Stop();
        _collapseTimer.Stop();

        var menu = BuildMenu();
        _openMenu = menu;
        menu.PlacementTarget = this;
        menu.Placement = PlacementMode.MousePoint;
        menu.Closed += (_, _) =>
        {
            _openMenu = null;
            if (_state == ViewState.Expanded && !IsMouseOver)
            {
                _collapseTimer.Start();
            }
        };
        menu.IsOpen = true;
        e.Handled = true;
    }

    private ContextMenu BuildMenu()
    {
        var menu = new ContextMenu();

        menu.Items.Add(Item("立即刷新", async () => await RefreshAsync()));
        menu.Items.Add(Item("打开用量详情", OpenUsage));
        menu.Items.Add(new Separator());

        menu.Items.Add(CheckedItem("显示剩余额度", _settings.ShowRemaining, () =>
        {
            _settings.ShowRemaining = true;
            _viewModel.ApplySettings(_settings);
            SaveSettings();
        }));
        menu.Items.Add(CheckedItem("显示已使用", !_settings.ShowRemaining, () =>
        {
            _settings.ShowRemaining = false;
            _viewModel.ApplySettings(_settings);
            SaveSettings();
        }));

        var interval = new MenuItem { Header = "刷新间隔" };
        foreach (var minutes in new[] { 1, 2, 3, 5, 10, 15, 30, 60 })
        {
            interval.Items.Add(CheckedItem($"{minutes} 分钟", _settings.RefreshMinutes == minutes, () =>
            {
                _settings.RefreshMinutes = minutes;
                _viewModel.ApplySettings(_settings);
                _refreshTimer.Stop();
                _refreshTimer.Interval = TimeSpan.FromMinutes(minutes);
                _refreshTimer.Start();
                SaveSettings();
            }));
        }
        menu.Items.Add(interval);

        menu.Items.Add(CheckedItem("窗口置顶", _settings.AlwaysOnTop, () =>
        {
            _settings.AlwaysOnTop = !_settings.AlwaysOnTop;
            Topmost = _settings.AlwaysOnTop;
            SaveSettings();
        }));

        menu.Items.Add(new Separator());

        if (_state == ViewState.Docked)
        {
            menu.Items.Add(Item("脱离边缘", UndockToBall));
        }

        menu.Items.Add(Item("重置位置", ResetPosition));
        menu.Items.Add(Item("打开数据目录", OpenDataFolder));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("退出", () => Application.Current.Shutdown()));

        return menu;
    }

    private static MenuItem Item(string header, Action action)
    {
        var item = new MenuItem { Header = header };
        item.Click += (_, _) => action();
        return item;
    }

    private static MenuItem CheckedItem(string header, bool isChecked, Action action)
    {
        var item = new MenuItem { Header = header, IsCheckable = true, IsChecked = isChecked };
        item.Click += (_, _) => action();
        return item;
    }

    private void UndockToBall()
    {
        _ballLeft = Left + (Width - BallWidth) / 2;
        _ballTop = Top + (Height - BallHeight) / 2;
        _dockEdge = DockEdge.None;
        ApplyState(ViewState.Ball, animate: true);
    }

    private void ResetPosition()
    {
        var work = SystemParameters.WorkArea;
        _ballLeft = work.Right - BallWidth - 32;
        _ballTop = work.Bottom - BallHeight - 48;
        _dockEdge = DockEdge.None;
        ApplyState(ViewState.Ball, animate: true);
    }

    private void OpenUsage()
    {
        var url = _viewModel.UsageUrl ?? new Uri("https://opencode.ai/console");
        try
        {
            Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true });
        }
        catch
        {
            // Opening a browser is best-effort.
        }
    }

    private void OpenDataFolder()
    {
        try
        {
            Directory.CreateDirectory(AppSettingsStore.Folder);
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{AppSettingsStore.Folder}\"",
                UseShellExecute = true,
            });
        }
        catch
        {
        }
    }

}
