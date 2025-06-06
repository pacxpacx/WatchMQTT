import SwiftUI
import WatchConnectivity

struct ContentView: View {
    @ObservedObject private var phoneMessages = WatchConnectivityManager.shared

    var body: some View {
        VStack(spacing: 12) {
            Text("MQTT Relay")
                .font(.headline)
            Text(phoneMessages.lastMessage.isEmpty ? "No messages" : phoneMessages.lastMessage)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
