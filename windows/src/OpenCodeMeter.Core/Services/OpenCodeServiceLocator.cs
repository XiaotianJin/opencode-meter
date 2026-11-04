using System.Text.Json;
using OpenCodeMeter.Core.Models;

namespace OpenCodeMeter.Core.Services;

/// <summary>
/// Finds the registration file that the OpenCode desktop app rewrites on every
/// start. The port can change at any time, so callers should re-discover instead
/// of caching the URL.
/// </summary>
public static class OpenCodeServiceLocator
{
    public static IReadOnlyList<string> CandidatePaths()
    {
        var paths = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        void Add(string? path)
        {
            if (string.IsNullOrWhiteSpace(path)) return;
            path = Environment.ExpandEnvironmentVariables(path.Trim());
            if (seen.Add(path)) paths.Add(path);
        }

        Add(Environment.GetEnvironmentVariable("OPENCODE_SERVICE_FILE"));

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        Add(Path.Combine(home, ".local", "state", "opencode", "service.json"));
        Add(Path.Combine(home, ".config", "opencode", "service.json"));

        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        Add(Path.Combine(roaming, "opencode", "service.json"));
        Add(Path.Combine(local, "opencode", "service.json"));
        Add(Path.Combine(roaming, "ai.opencode.desktop", "service.json"));
        Add(Path.Combine(local, "ai.opencode.desktop", "service.json"));

        return paths;
    }

    public static OpenCodeService? Discover()
    {
        foreach (var path in CandidatePaths())
        {
            if (!File.Exists(path)) continue;
            try
            {
                using var stream = File.OpenRead(path);
                using var document = JsonDocument.Parse(stream);
                var root = document.RootElement;

                if (!root.TryGetProperty("url", out var urlElement) ||
                    !root.TryGetProperty("password", out var passwordElement))
                {
                    continue;
                }

                var rawUrl = urlElement.GetString();
                var password = passwordElement.GetString();
                if (string.IsNullOrWhiteSpace(rawUrl) ||
                    string.IsNullOrWhiteSpace(password) ||
                    !Uri.TryCreate(rawUrl, UriKind.Absolute, out var url))
                {
                    continue;
                }

                if (url.Scheme != Uri.UriSchemeHttp && url.Scheme != Uri.UriSchemeHttps) continue;
                return new OpenCodeService(url, password, path);
            }
            catch (IOException)
            {
                // The desktop app may be rewriting the file; try the next candidate.
            }
            catch (JsonException)
            {
                // Same: a partial write must not take the meter down.
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        return null;
    }
}
