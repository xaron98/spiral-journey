import WidgetKit
import SwiftUI

@main
struct SpiralWidgetBundle: WidgetBundle {
    var body: some Widget {
        CompositeScoreWidget()
        SleepDurationWidget()
        AcrophaseWidget()
    }
}
