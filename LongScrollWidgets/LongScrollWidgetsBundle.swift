import SwiftUI
import WidgetKit

@main
struct LongScrollWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LongScrollCaptureControl()
        LongScrollPageControl()
        LongScrollLiveActivity()
    }
}
