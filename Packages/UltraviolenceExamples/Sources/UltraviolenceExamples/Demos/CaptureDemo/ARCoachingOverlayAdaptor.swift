#if os(iOS)
import ARKit
import SwiftUI
import UltraviolenceUI

struct ARCoachingOverlayAdaptor: View {
    let session: ARSession

    var body: some View {
        ViewAdaptor {
            ARCoachingOverlayView()
        }
        update: { (coachingOverlay: ARCoachingOverlayView) in
            coachingOverlay.session = session
        }
    }
}

#endif
