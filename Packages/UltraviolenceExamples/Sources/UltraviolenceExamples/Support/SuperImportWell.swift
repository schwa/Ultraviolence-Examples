import SwiftUI
import UltraviolenceSupport
import UniformTypeIdentifiers

struct SuperImportWell <Content>: View where Content: View {
    var allowedContentTypes: [UTType]
    var content: (URL) -> Content

    @Binding
    private var url: URL?

    @State
    private var helper: SuperImportHelper

    init(url: Binding<URL?>, identifier: String, allowedContentTypes: [UTType], content: @escaping (URL) -> Content) {
        self._url = url
        self.allowedContentTypes = allowedContentTypes
        self.content = content
        self._helper = State(initialValue: SuperImportHelper(identifier: identifier, allowedContentTypes: allowedContentTypes))
    }

    var body: some View {
        Group {
            if let url = helper.url {
                content(url)
            }
            else {
                ContentUnavailableView("No File", systemImage: "exclamationmark.triangle")
                //                    .onDrop(of: allowedContentTypes, isTargeted: $isDropTargeted) { providers in
                //                        if let provider = providers.first {
                //                            do {
                //                                //try helper.storeImportedFile(at: url)
                //                            }
                //                            catch {
                //                                print("Failed to store imported file: \(error)")
                //                            }
                //                        }
                //                        return false
                //                    }
            }
        }
        .onChange(of: helper.url, initial: true) {
            url = helper.url
        }
    }
}
