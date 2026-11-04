using System.Text;

namespace OpenCodeMeter.App.Services;

/// <summary>
/// Detects when the current foreground window is a real full-screen window
/// (game, video, browser fullscreen, UWP app, lock screen ...). The meter
/// should stay out of the way in those cases.
/// </summary>
internal static class FullscreenDetector
{
    private const int DwmwaExtendedFrameBounds = 9;
    private const int BoundsTolerance = 8;

    private static readonly HashSet<string> ShellWindowClasses = new(StringComparer.Ordinal)
    {
        "Progman",
        "WorkerW",
        "Shell_TrayWnd",
        "Shell_SecondaryTrayWnd",
    };

    public static bool IsForegroundFullscreen(IntPtr ownWindow)
    {
        var foreground = NativeMethods.GetForegroundWindow();
        if (foreground == IntPtr.Zero || foreground == ownWindow) return false;

        NativeMethods.GetWindowThreadProcessId(foreground, out var processId);
        if (processId == (uint)Environment.ProcessId) return false;

        if (!NativeMethods.IsWindowVisible(foreground) || NativeMethods.IsIconic(foreground)) return false;

        var className = GetClassName(foreground);
        if (ShellWindowClasses.Contains(className)) return false;

        if (!TryGetBounds(foreground, out var bounds)) return false;

        var monitor = NativeMethods.MonitorFromWindow(foreground, NativeMethods.MonitorDefaultToNearest);
        if (monitor == IntPtr.Zero) return false;

        var info = new NativeMethods.MONITORINFO
        {
            cbSize = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.MONITORINFO>(),
        };
        if (!NativeMethods.GetMonitorInfo(monitor, ref info)) return false;

        var screen = info.rcMonitor;
        return bounds.Left <= screen.Left + BoundsTolerance &&
               bounds.Top <= screen.Top + BoundsTolerance &&
               bounds.Right >= screen.Right - BoundsTolerance &&
               bounds.Bottom >= screen.Bottom - BoundsTolerance;
    }

    private static bool TryGetBounds(IntPtr window, out NativeMethods.RECT bounds)
    {
        // Driven by DWM for the visible frame (browsers and UWP can report
        // invisible resize borders through GetWindowRect).
        var result = NativeMethods.DwmGetWindowAttribute(
            window,
            DwmwaExtendedFrameBounds,
            out bounds,
            System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.RECT>());

        if (result == 0 && bounds.Right > bounds.Left && bounds.Bottom > bounds.Top)
        {
            return true;
        }

        return NativeMethods.GetWindowRect(window, out bounds);
    }

    private static string GetClassName(IntPtr window)
    {
        var buffer = new StringBuilder(256);
        var length = NativeMethods.GetClassName(window, buffer, buffer.Capacity);
        return length > 0 ? buffer.ToString(0, length) : string.Empty;
    }
}
