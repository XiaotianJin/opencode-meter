namespace OpenCodeMeter.Core.Services;

public static class ResetFormatter
{
    /// <summary>Compact ASCII countdown that fits inside the rings.</summary>
    public static string Compact(DateTimeOffset? resetsAt, DateTimeOffset? now = null)
    {
        if (resetsAt is null) return "—";

        var seconds = (resetsAt.Value - (now ?? DateTimeOffset.Now)).TotalSeconds;
        if (seconds <= 0) return "即将重置";

        var minutes = (long)(seconds / 60);
        var days = minutes / 1440;
        var hours = (minutes % 1440) / 60;
        var mins = minutes % 60;

        if (days > 0) return $"{days}d{hours}h";
        if (hours > 0) return $"{hours}h{mins}m";
        return $"{Math.Max(1, mins)}m";
    }

    public static string Clock(DateTimeOffset? value) => value?.ToString("HH:mm") ?? "--:--";
}
