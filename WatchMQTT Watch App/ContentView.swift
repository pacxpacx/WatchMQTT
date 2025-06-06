import SwiftUI
import Network

struct ContentView: View {
    @State private var connectionResult: String = ""
    @State private var isTesting = false
    @State private var lastMQTTMessage: String = ""
    @State private var autoTestDone = false
    @State private var ipAddress: String = "192.168.33.111"
    @State private var port: String = "9001"
    @State private var webSocketPath: String = "/ws"
    @State private var topic: String = "home/button"

    // MQTT/WebSocket connection state
    @State private var isConnected = false
    @State private var webSocketTask: URLSessionWebSocketTask?

    // Encode MQTT remaining length using variable-length format
    private func encodeRemainingLength(_ len: Int) -> [UInt8] {
        var value = len
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value % 128)
            value /= 128
            if value > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value > 0
        return bytes
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                TextField("IP Address", text: $ipAddress)
                TextField("Port", text: $port)
                TextField("WebSocket Path", text: $webSocketPath)
                TextField("Topic", text: $topic)
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

    // Request permission to access the local network. Without this the watch
    // cannot open connections to LAN addresses and the broker connection will
    // fail with an NECP policy error.
    func requestLocalNetworkAccessIfNeeded() {
        guard let host = IPv4Address(ipAddress), let portValue = UInt16(port) else {
            return
        }
        let endpoint = NWEndpoint.hostPort(host: .ipv4(host), port: NWEndpoint.Port(rawValue: portValue)!)
        let params = NWParameters.udp
        let connection = NWConnection(to: endpoint, using: params)
        connection.stateUpdateHandler = { state in
            // Cancel once the framework has triggered the local network prompt.
            switch state {
            case .ready:
                connection.send(content: Data([0]), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global())
    }

    /// Send a small UDP packet to trigger the local network permission prompt
    /// and provide simple connectivity feedback in `connectionResult`.
    func testAllLocalNetwork() {
        isTesting = true
        connectionResult = "Testing network…"
        testUDP()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isTesting = false
        }
    }

    private func testUDP() {
        guard let host = IPv4Address(ipAddress), let portValue = UInt16(port) else {
            self.connectionResult = "Invalid address"
            return
        }

        let endpoint = NWEndpoint.hostPort(host: .ipv4(host), port: NWEndpoint.Port(rawValue: portValue)!)
        let params = NWParameters.udp
        let conn = NWConnection(to: endpoint, using: params)
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                self.connectionResult = "UDP reachable"
                conn.cancel()
            }
            if case .failed(let error) = state {
                self.connectionResult = "UDP error: \(error.localizedDescription)"
                conn.cancel()
            }
        }
        conn.start(queue: .global())
        conn.send(content: "ping".data(using: .utf8), completion: .contentProcessed { _ in })
    }

    // --- Updated connect/disconnect logic ---
    func connectToMQTTBroker() {
        guard let portValue = UInt16(port) else {
            lastMQTTMessage = "Invalid port number."
            return
        }
        let sanitizedPath = webSocketPath.hasPrefix("/") ? webSocketPath : "/" + webSocketPath
        let urlString = "ws://\(ipAddress):\(portValue)\(sanitizedPath)"
        guard let mqttUrl = URL(string: urlString) else {
            lastMQTTMessage = "Invalid URL."
            return
        }
        // If already connected, disconnect first
        if isConnected {
            disconnectFromMQTTBroker()
        }
        var request = URLRequest(url: mqttUrl)
        request.addValue("mqtt", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = URLSession.shared.webSocketTask(with: request)
        webSocketTask = task
        isConnected = false
        task.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.sendMQTTConnectPacket()
            self.startReceiving()
        }
    }

    private func startReceiving() {
        webSocketTask?.receive { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self.lastMQTTMessage = "MQTT WebSocket Error: \(error.localizedDescription)"
                    self.isConnected = false
                    self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                    self.webSocketTask = nil
                case .success(let message):
                    switch message {
                    case .string(let str):
                        self.lastMQTTMessage = "Received: \(str)"
                    case .data(let data):
                        if data.count >= 4 && data[0] == 0x20 && data[1] == 0x02 {
                            let status = data[3]
                            if status == 0 {
                                self.lastMQTTMessage = "MQTT CONNACK received"
                                self.isConnected = true
                                self.sendMQTTSubscribePacket()
                            } else {
                                self.lastMQTTMessage = "Connection refused: \(status)"
                                self.isConnected = false
                            }
                        } else {
                            self.lastMQTTMessage = "Received binary (\(data.count) bytes)"
                        }
                    @unknown default:
                        self.lastMQTTMessage = "Unknown MQTT message"
                    }
                }
                if self.isConnected {
                    self.startReceiving()
                } else if self.webSocketTask != nil {
                    self.startReceiving()
                }
            }
        }
    }

    private func sendMQTTConnectPacket() {
        let clientId = "WatchMQTT-\(UUID().uuidString.prefix(8))"
        let username = "mqttuser"
        let password = "mqttpass"

        func mqttString(_ string: String) -> [UInt8] {
            let utf8 = Array(string.utf8)
            let len = UInt16(utf8.count)
            return [UInt8(len >> 8), UInt8(len & 0xFF)] + utf8
        }

        var variableHeader: [UInt8] = []
        variableHeader += mqttString("MQTT")
        variableHeader += [0x04]
        variableHeader += [0xC2]
        variableHeader += [0x00, 0x3C]

        var payload: [UInt8] = []
        payload += mqttString(clientId)
        payload += mqttString(username)
        payload += mqttString(password)

        let remainingLength = variableHeader.count + payload.count
        let connectPacket: [UInt8] = [0x10] + encodeRemainingLength(remainingLength) + variableHeader + payload

        webSocketTask?.send(.data(Data(connectPacket))) { error in
            if let error = error {
                self.lastMQTTMessage = "CONNECT send error: \(error.localizedDescription)"
            }
        }
    }

    private func sendMQTTSubscribePacket() {
        func mqttString(_ string: String) -> [UInt8] {
            let utf8 = Array(string.utf8)
            let len = UInt16(utf8.count)
            return [UInt8(len >> 8), UInt8(len & 0xFF)] + utf8
        }

        let packetIdentifier: UInt16 = 1
        let topicFilter = mqttString(topic)
        let subscribePayload: [UInt8] = topicFilter + [0x00]
        let identifierBytes: [UInt8] = [UInt8(packetIdentifier >> 8), UInt8(packetIdentifier & 0xFF)]
        let remainingLength = identifierBytes.count + subscribePayload.count
        let subscribePacket: [UInt8] = [0x82] + encodeRemainingLength(remainingLength) + identifierBytes + subscribePayload

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            webSocketTask?.send(.data(Data(subscribePacket))) { error in
                if let error = error {
                    self.lastMQTTMessage = "SUBSCRIBE send error: \(error.localizedDescription)"
                }
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
