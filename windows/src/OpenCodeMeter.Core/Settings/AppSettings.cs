using System.Text.Json;
using System.Text.Json.Serialization;

namespace OpenCodeMeter.Core.Settings;

public enum WidgetMode
{
    Ball,
    Docked,
}

public enum DockEdge
{
    None,
    Left,
    Right,
}

public sealed class AppSettings
{
    public bool ShowRemaining { get; set; } = true;
    public int RefreshMinutes { get; set; } = 3;
    public bool AlwaysOnTop { get; set; } = true;

    /// <summary>Last floating-ball position, in WPF device-independent units.</summary>
    public double? BallLeft { get; set; }
    public double? BallTop { get; set; }

    public WidgetMode Mode { get; set; } = WidgetMode.Ball;
    public DockEdge DockEdge { get; set; } = DockEdge.None;
    public double? DockLeft { get; set; }
    public double? DockTop { get; set; }

    public void Normalize()
    {
        RefreshMinutes = Math.Clamp(RefreshMinutes, 1, 60);
        if (DockEdge is not (DockEdge.Left or DockEdge.Right))
        {
            DockEdge = DockEdge.None;
            if (Mode == WidgetMode.Docked) Mode = WidgetMode.Ball;
        }
    }
}

public static class AppSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static string Folder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenCodeMeter");

    public static string FilePath => Path.Combine(Folder, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var json = File.ReadAllText(FilePath);
                var settings = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions) ?? new AppSettings();
                settings.Normalize();
                return settings;
            }
        }
        catch (IOException)
        {
        }
        catch (JsonException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }

        return new AppSettings();
    }

    public static void Save(AppSettings settings)
    {
        settings.Normalize();
        try
        {
            Directory.CreateDirectory(Folder);
            var json = JsonSerializer.Serialize(settings, JsonOptions);
            var temporary = FilePath + ".tmp";
            File.WriteAllText(temporary, json);
            File.Move(temporary, FilePath, overwrite: true);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
