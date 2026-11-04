using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using OpenCodeMeter.Core.Models;

namespace OpenCodeMeter.Core.Services;

public sealed class UsageClient : IDisposable
{
    private readonly HttpClient _http;
    private readonly bool _ownsHttpClient;

    public UsageClient(HttpClient? httpClient = null)
    {
        if (httpClient is null)
        {
            _http = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
            _ownsHttpClient = true;
        }
        else
        {
            _http = httpClient;
        }
    }

    public async Task<UsageSnapshot> FetchAsync(OpenCodeService service, CancellationToken cancellationToken = default)
    {
        Uri endpoint;
        try
        {
            endpoint = new Uri(service.Url, "api/experimental/usage/limits");
        }
        catch (UriFormatException ex)
        {
            throw new UsageException(UsageError.Malformed, ex.Message);
        }

        using var request = new HttpRequestMessage(HttpMethod.Get, endpoint);
        var basic = Convert.ToBase64String(Encoding.UTF8.GetBytes($"opencode:{service.Password}"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Basic", basic);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.CacheControl = new CacheControlHeaderValue { NoCache = true };

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new UsageException(UsageError.Network);
        }
        catch (HttpRequestException)
        {
            throw new UsageException(UsageError.Network);
        }

        using (response)
        {
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                throw new UsageException(UsageError.Unauthorized);
            }

            if (response.StatusCode != HttpStatusCode.OK)
            {
                throw new UsageException(UsageError.Http, $"服务返回 HTTP {(int)response.StatusCode}");
            }

            string json;
            try
            {
                json = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                throw new UsageException(UsageError.Network);
            }
            catch (HttpRequestException)
            {
                throw new UsageException(UsageError.Network);
            }

            return Parse(json);
        }
    }

    public static UsageSnapshot Parse(string json)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(json);
        }
        catch (JsonException)
        {
            throw new UsageException(UsageError.Malformed);
        }

        using (document)
        {
            var root = document.RootElement;
            if (!root.TryGetProperty("data", out var data) || data.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
            {
                throw new UsageException(UsageError.NotSignedIn);
            }

            if (!data.TryGetProperty("go", out var go) || go.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
            {
                throw new UsageException(UsageError.Malformed);
            }

            UsageWindow? rolling = ParseWindow(go, "rolling");
            UsageWindow? weekly = ParseWindow(go, "weekly");
            UsageWindow? monthly = ParseWindow(go, "monthly");

            Uri? usageUrl = null;
            string? workspaceName = null;
            if (data.TryGetProperty("workspace", out var workspace) && workspace.ValueKind == JsonValueKind.Object)
            {
                if (workspace.TryGetProperty("usageURL", out var usageElement) &&
                    Uri.TryCreate(usageElement.GetString(), UriKind.Absolute, out var parsedUrl))
                {
                    usageUrl = parsedUrl;
                }

                if (workspace.TryGetProperty("name", out var nameElement))
                {
                    workspaceName = nameElement.GetString();
                }
            }

            return new UsageSnapshot(rolling, weekly, monthly, usageUrl, workspaceName);
        }
    }

    private static UsageWindow? ParseWindow(JsonElement go, string name)
    {
        if (!go.TryGetProperty(name, out var window) || window.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var used = window.TryGetProperty("percent", out var percent) && percent.TryGetDouble(out var p)
            ? p
            : 0;

        var limited = window.TryGetProperty("limited", out var limitedElement) &&
                      limitedElement.ValueKind == JsonValueKind.True;

        DateTimeOffset? resetsAt = null;
        if (window.TryGetProperty("resetsAt", out var resetElement) && resetElement.TryGetInt64(out var millis))
        {
            try
            {
                resetsAt = DateTimeOffset.FromUnixTimeMilliseconds(millis).ToLocalTime();
            }
            catch (ArgumentOutOfRangeException)
            {
            }
        }

        return new UsageWindow(used, limited, resetsAt);
    }

    public void Dispose()
    {
        if (_ownsHttpClient) _http.Dispose();
    }
}
