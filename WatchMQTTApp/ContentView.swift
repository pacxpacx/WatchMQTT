import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var mqttManager = MQTTManager()
    @State private var connectionStatus: String = "Disconnected"
    @State private var debugMessages: [String] = ["No messages yet"]
    @State private var cancellables = Set<AnyCancellable>()
    @State private var brokerAddress: String = "192.168.33.111"
    @State private var brokerPort: String = "9001"
    @State private var webSocketPath: String = "/ws"
    @State private var subscribeTopic: String = "home/button"

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MQTT Broker Address")
                        .font(.caption)
                    TextField("e.g. 192.168.33.111", text: $brokerAddress)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Text("Port")
                        .font(.caption)
                    TextField("e.g. 9001", text: $brokerPort)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Text("WebSocket Path")
                        .font(.caption)
                    TextField("e.g. /ws", text: $webSocketPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Text("Subscribe Topic")
                        .font(.caption)
                    TextField("e.g. home/button", text: $subscribeTopic)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.bottom, 10)

                Text("Connection Status:")
                    .font(.headline)
                Text(connectionStatus)
                    .foregroundColor(connectionStatus == "Connected" ? .green : .red)
                    .multilineTextAlignment(.center)

                Divider()

                HStack(spacing: 20) {
                    Button(action: {
                        self.debugMessages.append("WebSocket full URL string: ws://\(brokerAddress):\(brokerPort)\(webSocketPath)")
                        mqttManager.topic = subscribeTopic
                        mqttManager.connect(broker: brokerAddress, port: brokerPort, path: webSocketPath)
                    }) {
                        Text("Connect")
                            .padding()
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    }
                    Button(action: {
                        mqttManager.disconnect()
                    }) {
                        Text("Disconnect")
                            .padding()
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(8)
                    }
                    Button(action: {
                        self.debugMessages = ["No messages yet"]
                    }) {
                        Text("Clear Debug")
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                }

                Text("Debug Info:")
                    .font(.headline)
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading) {
                                ForEach(Array(debugMessages.enumerated()), id: \.offset) { idx, msg in
                                    Text(msg)
                                        .font(.body)
                                        .padding(.bottom, 2)
                                        .id(idx)
                                }
                            }
                            .frame(minHeight: geometry.size.height)
                            .padding(.bottom, 20)
                        }
                        .onChange(of: debugMessages) { _ in
                            if let last = debugMessages.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(minHeight: 220, maxHeight: 350)
            }
            .padding()
        }
        .onAppear {
            mqttManager.connectionStatusPublisher
                .receive(on: RunLoop.main)
                .sink { status in
                    self.connectionStatus = status
                }
                .store(in: &cancellables)

            mqttManager.debugMessagePublisher
                .receive(on: RunLoop.main)
                .sink { message in
                    if self.debugMessages == ["No messages yet"] {
                        self.debugMessages = [message]
                    } else {
                        self.debugMessages.append(message)
                    }
                }
                .store(in: &cancellables)

            // Do not auto-connect on appear; only connect via button.
        }
    }
}
