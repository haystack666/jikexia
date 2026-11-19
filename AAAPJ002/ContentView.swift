import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(macOS)
        welcomeContent
            .frame(minWidth: 480, minHeight: 320)
        #else
        ListeningRootView()
        #endif
    }

    private var welcomeContent: some View {
        VStack(spacing: 16) {
            Image(systemName: welcomeSymbol)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("即刻匣")
                .font(.largeTitle.bold())

            Text("从这里开始构建你的应用")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeSymbol: String {
        #if os(macOS)
        return "shippingbox"
        #else
        return "apps.iphone"
        #endif
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
