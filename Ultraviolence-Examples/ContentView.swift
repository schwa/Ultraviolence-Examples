import DemoKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        DemoPickerView(demos: allDemos)
    }
}

#Preview {
    ContentView()
}
