import SwiftUI
import WidgetKit

@main
struct OpenCodeMeterWidgetBundle: WidgetBundle {
    var body: some Widget {
        OpenCodeUsageWidget()
        OpenCodeRingsWidget()
    }
}
