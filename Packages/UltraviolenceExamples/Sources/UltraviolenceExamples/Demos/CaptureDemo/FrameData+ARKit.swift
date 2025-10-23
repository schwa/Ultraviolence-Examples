#if os(iOS)
import ARKit

extension FrameData {
    init(frame: ARFrame) {
        let camera = frame.camera
        let transform = camera.transform
        self.transform = [transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w, transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w, transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w, transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w]
        self.eulerAngles = [camera.eulerAngles.x, camera.eulerAngles.y, camera.eulerAngles.z]
        let intrinsics = camera.intrinsics
        self.intrinsics = [intrinsics.columns.0.x, intrinsics.columns.0.y, intrinsics.columns.0.z, intrinsics.columns.1.x, intrinsics.columns.1.y, intrinsics.columns.1.z, intrinsics.columns.2.x, intrinsics.columns.2.y, intrinsics.columns.2.z]
        self.imageResolution = [Float(camera.imageResolution.width), Float(camera.imageResolution.height)]
        self.exposureDuration = camera.exposureDuration
        self.exposureOffset = camera.exposureOffset
        self.timestamp = frame.timestamp
        switch camera.trackingState {
        case .normal:
            self.trackingState = "normal"
            self.trackingStateReason = nil
        case .notAvailable:
            self.trackingState = "notAvailable"
            self.trackingStateReason = nil
        case .limited(let reason):
            self.trackingState = "limited"
            switch reason {
            case .excessiveMotion:
                self.trackingStateReason = "excessiveMotion"
            case .insufficientFeatures:
                self.trackingStateReason = "insufficientFeatures"
            case .initializing:
                self.trackingStateReason = "initializing"
            case .relocalizing:
                self.trackingStateReason = "relocalizing"
            @unknown default:
                self.trackingStateReason = "unknown"
            }
        }
        if let lightEstimate = frame.lightEstimate {
            if let directionalLight = lightEstimate as? ARDirectionalLightEstimate {
                self.lightEstimate = FrameData.LightEstimateData(ambientIntensity: Float(lightEstimate.ambientIntensity), ambientColorTemperature: Float(lightEstimate.ambientColorTemperature), primaryLightDirection: [directionalLight.primaryLightDirection.x, directionalLight.primaryLightDirection.y, directionalLight.primaryLightDirection.z], primaryLightIntensity: Float(directionalLight.primaryLightIntensity))
            } else {
                self.lightEstimate = FrameData.LightEstimateData(ambientIntensity: Float(lightEstimate.ambientIntensity), ambientColorTemperature: Float(lightEstimate.ambientColorTemperature), primaryLightDirection: nil, primaryLightIntensity: nil)
            }
        } else {
            self.lightEstimate = nil
        }
    }
}

#endif
