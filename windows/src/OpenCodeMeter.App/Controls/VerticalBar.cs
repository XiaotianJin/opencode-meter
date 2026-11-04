using System.Windows;
using System.Windows.Media;

namespace OpenCodeMeter.App.Controls;

/// <summary>Vertical meter used by the edge-docked strip.</summary>
public sealed class VerticalBar : FrameworkElement
{
    public static readonly DependencyProperty ProgressProperty = DependencyProperty.Register(
        nameof(Progress),
        typeof(double),
        typeof(VerticalBar),
        new FrameworkPropertyMetadata(0d, FrameworkPropertyMetadataOptions.AffectsRender, null, CoerceProgress));

    public static readonly DependencyProperty FillBrushProperty = DependencyProperty.Register(
        nameof(FillBrush),
        typeof(Brush),
        typeof(VerticalBar),
        new FrameworkPropertyMetadata(Brushes.LimeGreen, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty TrackBrushProperty = DependencyProperty.Register(
        nameof(TrackBrush),
        typeof(Brush),
        typeof(VerticalBar),
        new FrameworkPropertyMetadata(new SolidColorBrush(Color.FromArgb(0x24, 0xFF, 0xFF, 0xFF)), FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty CornerRadiusProperty = DependencyProperty.Register(
        nameof(CornerRadius),
        typeof(double),
        typeof(VerticalBar),
        new FrameworkPropertyMetadata(5d, FrameworkPropertyMetadataOptions.AffectsRender));

    public double Progress
    {
        get => (double)GetValue(ProgressProperty);
        set => SetValue(ProgressProperty, value);
    }

    public Brush FillBrush
    {
        get => (Brush)GetValue(FillBrushProperty);
        set => SetValue(FillBrushProperty, value);
    }

    public Brush TrackBrush
    {
        get => (Brush)GetValue(TrackBrushProperty);
        set => SetValue(TrackBrushProperty, value);
    }

    public double CornerRadius
    {
        get => (double)GetValue(CornerRadiusProperty);
        set => SetValue(CornerRadiusProperty, value);
    }

    private static object CoerceProgress(DependencyObject d, object baseValue)
    {
        var value = (double)baseValue;
        return double.IsNaN(value) ? 0d : Math.Clamp(value, 0d, 1d);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);

        var width = ActualWidth;
        var height = ActualHeight;
        if (width <= 0 || height <= 0) return;

        var radius = Math.Min(CornerRadius, Math.Min(width, height) / 2);
        drawingContext.DrawRoundedRectangle(TrackBrush, null, new Rect(0, 0, width, height), radius, radius);

        if (Progress <= 0.001) return;

        var fillHeight = Math.Max(2, height * Progress);
        var rect = new Rect(0, height - fillHeight, width, fillHeight);
        drawingContext.DrawRoundedRectangle(FillBrush, null, rect, radius, radius);
    }
}
