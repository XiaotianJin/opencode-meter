namespace OpenCodeMeter.Core.Models;

/// <summary>
/// One allowance window (rolling 5h, weekly or monthly).
/// <see cref="UsedPercent"/> follows the service semantics: 0 means untouched,
/// 100 means the whole allowance is consumed.
/// </summary>
public sealed record UsageWindow(double UsedPercent, bool Limited, DateTimeOffset? ResetsAt)
{
    public double RemainingPercent => Math.Clamp(100 - UsedPercent, 0, 100);
}

public sealed record UsageSnapshot(
    UsageWindow? Rolling,
    UsageWindow? Weekly,
    UsageWindow? Monthly,
    Uri? UsageUrl,
    string? WorkspaceName)
{
    public bool AnyLimited =>
        Rolling?.Limited == true || Weekly?.Limited == true || Monthly?.Limited == true;
}

/// <summary>Connection details of the local OpenCode desktop service.</summary>
public sealed record OpenCodeService(Uri Url, string Password, string SourcePath);
