#if canImport(AppKit)
import SwiftUI
import Ultraviolence

public struct OffscreenDemoView: View {
    @State
    private var result: Result<CGImage, Error>?

    public init() {
        // This line intentionally left blank.
    }

    public var body: some View {
        ZStack {
            Color.black
            if case let .success(image) = result {
                Image(nsImage: NSImage(cgImage: image, size: .zero))
                    .resizable()
            }
        }
        .overlay(alignment: .bottom) {
            Group {
                if case let .success(image) = result {
                    Text("\(image)")
                }
                if case let .failure(error) = result {
                    Text("Failure: \(error)")
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding()
        }
        .task {
            do {
                let root = RedTriangle()

                let offscreenRenderer = try OffscreenRenderer(size: CGSize(width: 1_600, height: 1_200))
                result = .success(try offscreenRenderer.render(root).cgImage)
            }
            catch {
                result = .failure(error)
            }
        }
    }
}

extension OffscreenDemoView: DemoView {
}
#endif
