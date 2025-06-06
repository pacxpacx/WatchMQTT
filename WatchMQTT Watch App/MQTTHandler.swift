import Foundation

class MQTTHandler: NSObject, ObservableObject, MQTTWebSocketClientDelegate {
    private var client: MQTTWebSocketClient?
    private var username: String
    private var password: String
    @Published var topic: String
    @Published var lastMessage: String?
    @Published var connectionStatus: String = "Disconnected"
    @Published var lastError: String?

    init(topic: String = "home/button", username: String = "mqttuser", password: String = "mqttpass") {
        self.topic = topic
        self.username = username
        self.password = password
        super.init()
        let url = URL(string: "ws://192.168.33.111:80/ws")!  // Replace with your broker address
        client = MQTTWebSocketClient(
            url: url,
            clientId: "WatchMQTT-\(UUID().uuidString.prefix(8))",
            username: username,
            password: password,
            topic: topic
        )
        client?.delegate = self
    }

    func connect() {
        client?.connect()
    }

    func updateTopicAndReconnect(_ newTopic: String, username: String? = nil, password: String? = nil) {
        topic = newTopic
        if let username = username {
            self.username = username
        }
        if let password = password {
            self.password = password
        }
        let url = URL(string: "ws://192.168.33.111:80/ws")!  // Replace with your broker address
        client = MQTTWebSocketClient(
            url: url,
            clientId: "WatchMQTT-\(UUID().uuidString.prefix(8))",
            username: self.username,
            password: self.password,
            topic: topic
        )
        client?.delegate = self
        client?.connect()
    }

    // MARK: - Delegate Methods

    func mqttClientDidConnect(_ client: MQTTWebSocketClient) {
        DispatchQueue.main.async {
            self.connectionStatus = "Connected"
            self.lastError = nil
        }
        print("✅ MQTT Connected")
        // client.subscribe(topic: topic)
    }

    func mqttClient(_ client: MQTTWebSocketClient, didReceiveMessage message: String) {
        DispatchQueue.main.async {
            self.lastMessage = message
        }
        print("📩 Received message:", message)
    }

    func mqttClientDidDisconnect(_ client: MQTTWebSocketClient) {
        DispatchQueue.main.async {
            self.connectionStatus = "Disconnected"
        }
        print("❌ MQTT Disconnected")
    }
}
