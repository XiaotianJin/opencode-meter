using System.Windows;
using System.Windows.Media;

namespace OpenCodeMeter.App.Controls;

/// <summary>
/// A single circular gauge. The gap is centred on the bottom of the control so
/// the countdown labels can sit inside it.
/// </summary>
public sealed class RingGauge : FrameworkElement
{
    public static readonly DependencyProperty ProgressProperty = DependencyProperty.Register(
        nameof(Progress),
        typeof(double),
        typeof(RingGauge),
        new FrameworkPropertyMetadata(0d, FrameworkPropertyMetadataOptions.AffectsRender, null, CoerceProgress));

    public static readonly DependencyProperty RadiusProperty = DependencyProperty.Register(
        nameof(Radius),
        typeof(double),
        typeof(RingGauge),
        new FrameworkPropertyMetadata(0d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ThicknessProperty = DependencyProperty.Register(
        nameof(Thickness),
        typeof(double),
        typeof(RingGauge),
        new FrameworkPropertyMetadata(6d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty GapAngleProperty = DependencyProperty.Register(
        nameof(GapAngle),
        typeof(double),
        typeof(RingGauge),
        new FrameworkPropertyMetadata(64d, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty ProgressBrushProperty = DependencyProperty.Register(
        nameof(ProgressBrush),
        typeof(Brush),
        typeof(RingGauge),
        new FrameworkPropertyMetadata(Brushes.LimeGreen, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty TrackBrushProperty = DependencyProperty.Register(
        nameof(TrackBrush),
        typeof(Brush),
        typeof(RingGauge),
        new FrameworkPropertyMetadata(new SolidColorBrush(Color.FromArgb(0x24, 0xFF, 0xFF, 0xFF)), FrameworkPropertyMetadataOptions.AffectsRender));

    public double Progress
    {
        get => (double)GetValue(ProgressProperty);
        set => SetValue(ProgressProperty, value);
    }

    public double Radius
    {
        get => (double)GetValue(RadiusProperty);
        set => SetValue(RadiusProperty, value);
    }

    public double Thickness
    {
        get => (double)GetValue(ThicknessProperty);
        set => SetValue(ThicknessProperty, value);
    }

    public double GapAngle
    {
        get => (double)GetValue(GapAngleProperty);
        set => SetValue(GapAngleProperty, value);
    }

    public Brush ProgressBrush
    {
        get => (Brush)GetValue(ProgressBrushProperty);
        set => SetValue(ProgressBrushProperty, value);
    }

    public Brush TrackBrush
    {
        get => (Brush)GetValue(TrackBrushProperty);
        set => SetValue(TrackBrushProperty, value);
    }

    private static object CoerceProgress(DependencyObject d, object baseValue)
    {
        var value = (double)baseValue;
        return double.IsNaN(value) ? 0d : Math.Clamp(value, 0d, 1d);
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);

        var radius = Radius > 0 ? Radius : Math.Min(ActualWidth, ActualHeight) / 2 - Thickness / 2;
        if (radius <= 0 || ActualWidth <= 0 || ActualHeight <= 0) return;

        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        var gap = Math.Clamp(GapAngle, 0, 300);
        var start = 90 + gap / 2;
        var span = 360 - gap;

        DrawArc(drawingContext, center, radius, start, span, TrackBrush, Thickness);
        if (Progress > 0.001)
        {
            DrawArc(drawingContext, center, radius, start, span * Progress, ProgressBrush, Thickness);
        }
    }

    private static void DrawArc(
        DrawingContext drawingContext,
        Point center,
        double radius,
        double startAngle,
        double sweepAngle,
        Brush brush,
        double thickness)
    {
        if (sweepAngle <= 0.01 || brush is null) return;

        var pen = new Pen(brush, thickness)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round,
        };
        pen.Freeze();

        if (sweepAngle >= 359.99)
        {
            drawingContext.DrawEllipse(null, pen, center, radius, radius);
            return;
        }

        var start = PointOnCircle(center, radius, startAngle);
        var end = PointOnCircle(center, radius, startAngle + sweepAngle);

        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
        {
            context.BeginFigure(start, false, false);
            context.ArcTo(
                end,
                new Size(radius, radius),
                0,
                sweepAngle > 180,
                SweepDirection.Clockwise,
                true,
                false);
        }

        geometry.Freeze();
        drawingContext.DrawGeometry(null, pen, geometry);
    }

    private static Point PointOnCircle(Point center, double radius, double degrees)
    {
        var radians = degrees * Math.PI / 180;
        return new Point(
            center.X + radius * Math.Cos(radians),
            center.Y + radius * Math.Sin(radians));
    }
}
