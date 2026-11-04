using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media;
using OpenCodeMeter.Core.Models;
using OpenCodeMeter.Core.Services;
using OpenCodeMeter.Core.Settings;

namespace OpenCodeMeter.App.ViewModels;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private static readonly Brush NormalBrush = Freeze(Color.FromRgb(0x57, 0xD9, 0x8F));
    private static readonly Brush WarningBrush = Freeze(Color.FromRgb(0xF5, 0xBA, 0x4C));
    private static readonly Brush CriticalBrush = Freeze(Color.FromRgb(0xEF, 0x66, 0x66));
    private static readonly Brush MutedBrush = Freeze(Color.FromRgb(0x9E, 0xA6, 0xB8));
    private static readonly Brush EmptyBrush = Freeze(Color.FromRgb(0x6B, 0x71, 0x80));

    private AppSettings _settings = new();
    private UsageSnapshot? _snapshot;
    private DateTimeOffset? _updatedAt;
    private string? _error;
    private bool _refreshing;

    public event PropertyChangedEventHandler? PropertyChanged;

    public AppSettings Settings => _settings;

    public bool HasSnapshot => _snapshot is not null;

    public Uri? UsageUrl => _snapshot?.UsageUrl;

    public string StatusText
    {
        get
        {
            if (_error is not null) return _snapshot is null ? "未连接" : "离线";
            if (_refreshing) return "同步中";
            if (_snapshot?.AnyLimited == true) return "已限流";
            return "正常";
        }
    }

    public Brush StatusBrush
    {
        get
        {
            if (_error is not null) return _snapshot is null ? CriticalBrush : WarningBrush;
            if (_refreshing) return MutedBrush;
            if (_snapshot?.AnyLimited == true) return WarningBrush;
            return NormalBrush;
        }
    }

    public string StatusDetail => _error ?? "OpenCode Go 订阅额度";

    public string UpdatedTimeText => ResetFormatter.Clock(_updatedAt);

    public string UpdatedText => _updatedAt is null ? "尚未更新" : $"更新于 {_updatedAt:HH:mm}";

    public string UpdatedCaption => _error is null ? "最近更新" : "上次更新";

    public string RefreshCaption => $"每 {_settings.RefreshMinutes} 分钟刷新";

    public double RollingProgress => DisplayProgress(_snapshot?.Rolling);
    public double WeeklyProgress => DisplayProgress(_snapshot?.Weekly);
    public double MonthlyProgress => DisplayProgress(_snapshot?.Monthly);

    public string RollingPercentText => PercentText(_snapshot?.Rolling);
    public string WeeklyPercentText => PercentText(_snapshot?.Weekly);
    public string MonthlyPercentText => PercentText(_snapshot?.Monthly);

    public string RollingResetText => ResetFormatter.Compact(_snapshot?.Rolling?.ResetsAt);
    public string WeeklyResetText => ResetFormatter.Compact(_snapshot?.Weekly?.ResetsAt);
    public string MonthlyResetText => ResetFormatter.Compact(_snapshot?.Monthly?.ResetsAt);

    public string RollingGapText => $"5h  {RollingResetText}";
    public string WeeklyGapText => $"1w  {WeeklyResetText}";
    public string MonthlyGapText => $"1m  {MonthlyResetText}";

    public Brush RollingBrush => BrushFor(_snapshot?.Rolling);
    public Brush WeeklyBrush => BrushFor(_snapshot?.Weekly);
    public Brush MonthlyBrush => BrushFor(_snapshot?.Monthly);

    public string TooltipText
    {
        get
        {
            if (_snapshot is null)
            {
                return string.IsNullOrWhiteSpace(_error)
                    ? "尚未同步额度\n启动 OpenCode 后会自动刷新"
                    : $"尚未同步额度\n{_error}";
            }

            var lines = new[]
            {
                Line("5 小时", _snapshot.Rolling),
                Line("周限额", _snapshot.Weekly),
                Line("月限额", _snapshot.Monthly),
            };

            var footer = $"{UpdatedText} · {RefreshCaption}";
            return string.Join("\n", lines) +
                   $"\n\n{footer}" +
                   (string.IsNullOrWhiteSpace(_error) ? string.Empty : $"\n{_error}");
        }
    }

    public void ApplySettings(AppSettings settings)
    {
        _settings = settings;
        RaiseAll();
    }

    public void ApplySnapshot(UsageSnapshot snapshot, DateTimeOffset updatedAt)
    {
        _snapshot = snapshot;
        _updatedAt = updatedAt;
        _error = null;
        RaiseAll();
    }

    public void ApplyError(string message)
    {
        _error = message;
        RaiseAll();
    }

    public void SetRefreshing(bool refreshing)
    {
        _refreshing = refreshing;
        Raise(nameof(StatusText));
        Raise(nameof(StatusBrush));
    }

    /// <summary>Re-render countdowns without touching the network.</summary>
    public void Tick()
    {
        Raise(nameof(RollingResetText));
        Raise(nameof(WeeklyResetText));
        Raise(nameof(MonthlyResetText));
        Raise(nameof(RollingGapText));
        Raise(nameof(WeeklyGapText));
        Raise(nameof(MonthlyGapText));
        Raise(nameof(TooltipText));
        Raise(nameof(UpdatedText));
    }

    private double DisplayProgress(UsageWindow? window)
    {
        if (window is null) return 0;
        var value = _settings.ShowRemaining ? window.RemainingPercent : window.UsedPercent;
        return Math.Clamp(value / 100d, 0, 1);
    }

    private string PercentText(UsageWindow? window)
    {
        if (window is null) return "—";
        var value = _settings.ShowRemaining ? window.RemainingPercent : window.UsedPercent;
        return $"{Math.Round(value, MidpointRounding.AwayFromZero)}%";
    }

    private Brush BrushFor(UsageWindow? window)
    {
        if (window is null) return EmptyBrush;
        if (window.Limited || window.RemainingPercent <= 10) return CriticalBrush;
        if (window.RemainingPercent <= 25) return WarningBrush;
        return NormalBrush;
    }

    private string Line(string name, UsageWindow? window)
    {
        if (window is null) return $"{name}   —";
        var percent = _settings.ShowRemaining
            ? $"剩余 {Math.Round(window.RemainingPercent)}%"
            : $"已用 {Math.Round(window.UsedPercent)}%";
        var reset = ResetFormatter.Compact(window.ResetsAt);
        var resetText = reset is "即将重置" or "—" ? reset : $"{reset} 后重置";
        return $"{name}   {percent} · {resetText}";
    }

    private void RaiseAll()
    {
        foreach (var name in new[]
                 {
                     nameof(HasSnapshot), nameof(UsageUrl),
                     nameof(StatusText), nameof(StatusBrush), nameof(StatusDetail),
                     nameof(UpdatedTimeText), nameof(UpdatedText), nameof(UpdatedCaption),
                     nameof(RefreshCaption), nameof(TooltipText),
                     nameof(RollingProgress), nameof(WeeklyProgress), nameof(MonthlyProgress),
                     nameof(RollingPercentText), nameof(WeeklyPercentText), nameof(MonthlyPercentText),
                     nameof(RollingResetText), nameof(WeeklyResetText), nameof(MonthlyResetText),
                     nameof(RollingGapText), nameof(WeeklyGapText), nameof(MonthlyGapText),
                     nameof(RollingBrush), nameof(WeeklyBrush), nameof(MonthlyBrush),
                 })
        {
            Raise(name);
        }
    }

    private void Raise([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    private static Brush Freeze(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
