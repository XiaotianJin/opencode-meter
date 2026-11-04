namespace OpenCodeMeter.Core.Models;

public enum UsageError
{
    ServiceMissing,
    Unauthorized,
    NotSignedIn,
    Http,
    Network,
    Malformed,
}

public sealed class UsageException : Exception
{
    public UsageException(UsageError kind, string? detail = null)
        : base(detail ?? DefaultMessage(kind))
    {
        Kind = kind;
        Detail = detail;
    }

    public UsageError Kind { get; }

    public string? Detail { get; }

    public static string DefaultMessage(UsageError kind) => kind switch
    {
        UsageError.ServiceMissing => "未找到 OpenCode 服务，请先启动 OpenCode",
        UsageError.Unauthorized => "认证失败，请在 OpenCode 中重新登录",
        UsageError.NotSignedIn => "当前未登录 OpenCode 账号",
        UsageError.Http => "服务返回异常状态",
        UsageError.Network => "无法连接 OpenCode 本地服务",
        _ => "返回数据格式异常",
    };
}
