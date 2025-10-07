import GeometryLite3D
import Interaction3D
import Panels
import simd
import SwiftUI
import UltraviolenceSupport

// TODO: this is becoming a bit of a grab bag of features, consider splitting into smaller components
public struct WorldView<Content: View>: View {
    @Binding
    var projection: any ProjectionProtocol

    @Binding
    private var cameraMatrix: simd_float4x4

    @Binding
    private var targetMatrix: simd_float4x4?

    var content: Content

    @State
    private var cameraMode: CameraMode = .free

    @State
    private var freeCameraController: CameraControllerMode = .turntable

    @State
    private var isInspectorPresented = true

    @State
    private var turntableConstraint = TurntableControllerConstraint(target: .zero, radius: 5)

    public init(projection: Binding<any ProjectionProtocol>, cameraMatrix: Binding<simd_float4x4>, targetMatrix: Binding<simd_float4x4?> = .constant(nil), @ViewBuilder content: @escaping () -> Content) {
        self._projection = projection
        self._cameraMatrix = cameraMatrix
        self._targetMatrix = targetMatrix
        self.content = content()
    }

    public var body: some View {
        content
            .modifier(enabled: freeCameraController == .turntable, TurntableCameraController(constraint: $turntableConstraint, transform: $cameraMatrix))
            //            .modifier(RTSControllerModifier(cameraMatrix: $cameraMatrix))
            .toolbar {
                Button("Inspector", systemImage: "sidebar.right") {
                    isInspectorPresented.toggle()
                }
            }
            .panel(id: "cameraSettings", label: "Camera") {
                settingsView
            }
            .panel(id: "turntable", label: "Turntable") {
                TurntableConstraintEditor(value: $turntableConstraint)
            }
            .onChange(of: cameraMode) {
                switch cameraMode {
                case .fixed(let cameraAngle):
                    cameraMatrix = cameraAngle.matrix
                default:
                    break
                }
            }
            .inspector(isPresented: $isInspectorPresented) {
                // Display all registered panels
                Form {
                    Panels { panel in
                        Section(panel.label) {
                            panel.body
                        }
                    }
                }
            }
            .panelsHost()
    }

    var initialTurntableControllerConstraint: TurntableControllerConstraint {
        let target = targetMatrix?.translation ?? .zero
        let camera = cameraMatrix.translation
        let radius = length(target - camera)
        return TurntableControllerConstraint(target: target, radius: radius)
    }

    @ViewBuilder
    var settingsView: some View {
        Picker("Mode", selection: $cameraMode) {
            Text("Free").tag(CameraMode.free)
            ForEach(CameraAngle.allCases, id: \.self) { angle in
                Text("\(String(describing: angle))").tag(CameraMode.fixed(angle))
            }
        }

        Picker("Controller", selection: $freeCameraController) {
            ForEach(CameraControllerMode.allCases, id: \.self) { value in
                Text("\(String(describing: value))").tag(value)
            }
        }
    }
}

public enum CameraControllerMode: Hashable, CaseIterable {
    case turntable
    //    case arcball
    case flight
    //    case walk
    //    case hover
    //    case pan
}

public enum CameraMode: Hashable {
    case free
    case fixed(CameraAngle)
}

public enum CameraAngle: Hashable, CaseIterable {
    case top
    case bottom
    case left
    case right
    case front
    case back
}

extension CameraAngle {
    var matrix: simd_float4x4 {
        switch self {
        case .top:
            return LookAt(position: [0, 1, 0], target: [0, 0, 0], up: [0, 0, 1]).cameraMatrix
        case .bottom:
            return LookAt(position: [0, -1, 0], target: [0, 0, 0], up: [0, 0, -1]).cameraMatrix
        case .left:
            return LookAt(position: [-1, 0, 0], target: [0, 0, 0], up: [0, 1, 0]).cameraMatrix
        case .right:
            return LookAt(position: [1, 0, 0], target: [0, 0, 0], up: [0, 1, 0]).cameraMatrix
        case .front:
            return LookAt(position: [0, 0, 1], target: [0, 0, 0], up: [0, 1, 0]).cameraMatrix
        case .back:
            return LookAt(position: [0, 0, -1], target: [0, 0, 0], up: [0, 1, 0]).cameraMatrix
        }
    }
}
