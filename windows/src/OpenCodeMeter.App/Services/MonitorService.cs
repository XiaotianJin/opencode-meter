using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

namespace OpenCodeMeter.App.Services;

internal static class NativeMethods
{
    public const int GwlExstyle = -20;
    public const long WsExToolWindow = 0x00000080;
    public const uint MonitorDefaultToNearest = 2;

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    public static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    public static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr newLong);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }
}

internal static class MonitorService
{
    public static Rect GetWorkArea(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return SystemParameters.WorkArea;

        var monitor = NativeMethods.MonitorFromWindow(handle, NativeMethods.MonitorDefaultToNearest);
        var info = new NativeMethods.MONITORINFO
        {
            cbSize = Marshal.SizeOf<NativeMethods.MONITORINFO>(),
        };

        if (monitor == IntPtr.Zero || !NativeMethods.GetMonitorInfo(monitor, ref info))
        {
            return SystemParameters.WorkArea;
        }

        var transform = DeviceToDip(window);
        var topLeft = transform.Transform(new Point(info.rcWork.Left, info.rcWork.Top));
        var bottomRight = transform.Transform(new Point(info.rcWork.Right, info.rcWork.Bottom));
        return new Rect(topLeft, bottomRight);
    }

    public static Point GetCursorPosition(Window window)
    {
        if (!NativeMethods.GetCursorPos(out var point)) return new Point(0, 0);
        return DeviceToDip(window).Transform(new Point(point.X, point.Y));
    }

    public static Matrix DeviceToDip(Window window)
    {
        var source = PresentationSource.FromVisual(window);
        if (source?.CompositionTarget is not null)
        {
            return source.CompositionTarget.TransformFromDevice;
        }

        var dpi = VisualTreeHelper.GetDpi(window);
        return new Matrix(1d / dpi.DpiScaleX, 0, 0, 1d / dpi.DpiScaleY, 0, 0);
    }

    public static void HideFromAltTab(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;

        var exStyle = NativeMethods.GetWindowLongPtr(handle, NativeMethods.GwlExstyle).ToInt64();
        NativeMethods.SetWindowLongPtr(
            handle,
            NativeMethods.GwlExstyle,
            new IntPtr(exStyle | NativeMethods.WsExToolWindow));
    }

    public static void ClampTo(Rect workArea, ref double left, ref double top, double width, double height)
    {
        const double margin = 8;
        var maxLeft = Math.Max(workArea.Left + margin, workArea.Right - width - margin);
        var maxTop = Math.Max(workArea.Top + margin, workArea.Bottom - height - margin);
        left = Math.Clamp(left, workArea.Left + margin, maxLeft);
        top = Math.Clamp(top, workArea.Top + margin, maxTop);
    }

    public static bool IsVisible(Point point)
    {
        return point.X >= SystemParameters.VirtualScreenLeft &&
               point.X <= SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth &&
               point.Y >= SystemParameters.VirtualScreenTop &&
               point.Y <= SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight;
    }
}
