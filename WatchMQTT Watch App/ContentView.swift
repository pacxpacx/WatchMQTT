import SwiftUI
import Network

struct ContentView: View {
    @State private var connectionResult: String = ""
    @State private var isTesting = false
    @State private var lastMQTTMessage: String = ""
    @State private var autoTestDone = false
    @State private var ipAddress: String = "192.168.33.111"
    @State private var port: String = "9001"

    // MQTT/WebSocket connection state
    @State private var isConnected = false
    @State private var webSocketTask: URLSessionWebSocketTask?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                TextField("IP Address", text: $ipAddress)
                TextField("Port", text: $port)
                Image(systemName: "wifi")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Local Network Test")
                    .font(.headline)
                Button(action: testAllLocalNetwork) {
                    if isTesting {
                        ProgressView()
                    } else {
                        Text("Test Local Network Access")
                    }
                }
                .disabled(isTesting)
                Text(connectionResult)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(connectionResult.contains("Connected") ? .green : .red)

                Divider()
                    .padding(.vertical, 6)

                // --- New Buttons and Status ---
                HStack {
                    Button(action: connectToMQTTBroker) {
                        Text("Connect")
                    }
                    .disabled(isConnected)
                    
                    Button(action: disconnectFromMQTTBroker) {
                        Text("Disconnect")
                    }
                    .disabled(!isConnected)
                }
                Text(isConnected ? "Connected" : "Disconnected")
                    .foregroundColor(isConnected ? .green : .red)
                    .font(.subheadline)
                
                Text("Last MQTT Message:")
                    .font(.subheadline)
                Text(lastMQTTMessage.isEmpty ? "None yet" : lastMQTTMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()
            .onAppear {
                if !autoTestDone {
                    autoTestDone = true
                    requestLocalNetworkAccessIfNeeded()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        testAllLocalNetwork()
                    }
                }
            }
        }
    }

    func requestLocalNetworkAccessIfNeeded() { /* ... unchanged ... */ }
    func testAllLocalNetwork() { /* ... unchanged ... */ }
    func testUDP() { /* ... unchanged ... */ }

    // --- Updated connect/disconnect logic ---
    func connectToMQTTBroker() {
        guard let portValue = UInt16(port) else {
            lastMQTTMessage = "Invalid port number."
            return
        }
        guard let mqttUrl = URL(string: "ws://\(ipAddress):\(portValue)") else {
            lastMQTTMessage = "Invalid URL."
            return
        }
        // If already connected, disconnect first
        if isConnected {
            disconnectFromMQTTBroker()
        }
        let task = URLSession.shared.webSocketTask(with: mqttUrl)
        webSocketTask = task
        isConnected = true
        task.resume()
        task.receive { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self.lastMQTTMessage = "MQTT WebSocket Error: \(error.localizedDescription)"
                    self.isConnected = false
                case .success(let message):
                    switch message {
                    case .string(let str):
                        self.lastMQTTMessage = "Received: \(str)"
                    case .data(let data):
                        self.lastMQTTMessage = "Received binary (\(data.count) bytes)"
                    @unknown default:
                        self.lastMQTTMessage = "Unknown MQTT message"
                    }
                }
                // Keep connection open, do not cancel here
            }
        }
    }
    
    func disconnectFromMQTTBroker() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        lastMQTTMessage = "Disconnected."
    }
}

#Preview {
    ContentView()
}
