import Foundation
import Combine
import WatchConnectivity

/// Handles the MQTT connection on iOS and forwards received messages to the
/// watch via ``WatchConnectivityManager``.

class MQTTManager: ObservableObject {
    @Published var isConnected = false

    var webSocketTask: URLSessionWebSocketTask?
    let debugMessagePublisher = PassthroughSubject<String, Never>()
    let connectionStatusPublisher = PassthroughSubject<String, Never>()

    @Published var brokerAddress: String = "192.168.33.111"
    @Published var port: String = "80"
    @Published var clientID: String = "Watch"
    @Published var username: String = "test"
    @Published var password: String = "test"
    @Published var webSocketPath: String = "/ws"
    @Published var topic: String = "home/button"

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

    /// Decode the MQTT remaining length field starting at `index`.
    /// Returns the value and the number of bytes consumed.
    private func decodeRemainingLength(_ data: [UInt8], index: inout Int) -> Int {
        var multiplier = 1
        var value = 0
        var encodedByte: UInt8 = 0
        repeat {
            guard index < data.count else { return 0 }
            encodedByte = data[index]
            value += Int(encodedByte & 127) * multiplier
            multiplier *= 128
            index += 1
        } while (encodedByte & 128) != 0 && index < data.count
        return value
    }

    func connect(broker: String, port: String, path: String? = nil) {
        self.brokerAddress = broker
        if let path = path {
            self.webSocketPath = path
        }

        guard let portInt = Int(port), portInt > 0 && portInt < 65536 else {
            debugMessagePublisher.send("Invalid port number")
            return
        }

        self.port = String(portInt)

        guard webSocketTask == nil else {
            debugMessagePublisher.send("Already connected or connecting.")
            return
        }

        let sanitizedPath = webSocketPath.hasPrefix("/") ? webSocketPath : "/" + webSocketPath
        let urlString = "ws://\(brokerAddress):\(portInt)\(sanitizedPath)"
        guard let url = URL(string: urlString) else {
            debugMessagePublisher.send("Invalid URL.")
            return
        }

        let session = URLSession(configuration: .default)
        var request = URLRequest(url: url)
        request.addValue("mqtt", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        debugMessagePublisher.send("WebSocket task created with URL: \(urlString)")
        task.resume()
        debugMessagePublisher.send("WebSocket task resumed")
        debugMessagePublisher.send("WebSocket connecting...")

        // Wait a moment for the socket to open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.sendMQTTConnectPacket()
        }
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        connectionStatusPublisher.send("Disconnected")
        debugMessagePublisher.send("WebSocket disconnected.")
    }

    func sendMQTTConnectPacket() {
        func encodeString(_ string: String) -> [UInt8] {
            let utf8 = Array(string.utf8)
            let len = UInt16(utf8.count)
            return [UInt8(len >> 8), UInt8(len & 0xFF)] + utf8
        }

        // Variable header
        var variableHeader: [UInt8] = []
        variableHeader += encodeString("MQTT") // Protocol Name
        variableHeader += [0x04] // Protocol Level (3.1.1)
        variableHeader += [0xC2] // Connect Flags: Clean Session + Username + Password
        variableHeader += [0x00, 0x3c] // Keep Alive 60 seconds

        // Payload
        var payload: [UInt8] = []
        payload += encodeString(clientID)
        payload += encodeString(username)
        payload += encodeString(password)

        // Remaining Length
        let remainingLength = variableHeader.count + payload.count

        var packet: [UInt8] = [0x10] // CONNECT
        packet += encodeRemainingLength(remainingLength)
        packet += variableHeader
        packet += payload

        // Debug
        let packetHexString = packet.map { String(format: "%02X", $0) }.joined(separator: " ")
        debugMessagePublisher.send("MQTT CONNECT Packet (hex): \(packetHexString)")

        let data = Data(packet)

        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error = error {
                self?.debugMessagePublisher.send("Failed to send MQTT CONNECT: \(error.localizedDescription)")
                self?.connectionStatusPublisher.send("Connect Send Failed")
            } else {
                self?.debugMessagePublisher.send("MQTT CONNECT packet sent (correct encoding)")
                self?.receiveLoop()
            }
        }
    }

    // Listen for ALL incoming data
    func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                self?.debugMessagePublisher.send("Receive error: \(error.localizedDescription)")
                self?.connectionStatusPublisher.send("Receive Error")
                self?.isConnected = false
                self?.webSocketTask?.cancel(with: .goingAway, reason: nil)
                self?.webSocketTask = nil
            case .success(let message):
                switch message {
                case .data(let data):
                    let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                    self?.debugMessagePublisher.send("Received data: \(hex) (\(data.count) bytes)")
                    // Check for CONNACK (0x20 0x02 0x00 0x00)
                    if data.count >= 4 && data[0] == 0x20 && data[1] == 0x02 {
                        let connackStatus = data[3]
                        if connackStatus == 0x00 {
                            self?.isConnected = true
                            self?.connectionStatusPublisher.send("Connected")
                            self?.debugMessagePublisher.send("MQTT CONNACK received, connection accepted")
                            self?.sendMQTTSubscribePacket()
                        } else {
                            self?.isConnected = false
                            self?.connectionStatusPublisher.send("Connection Refused: \(connackStatus)")
                            self?.debugMessagePublisher.send("MQTT CONNACK refused, code: \(connackStatus)")
                        }
                    } else if data.count > 2 && (data[0] & 0xF0) == 0x30 {
                        // Basic PUBLISH decoding for QoS 0 messages
                        var idx = 1
                        _ = self?.decodeRemainingLength(Array(data), index: &idx)
                        guard idx + 2 <= data.count else { break }
                        let topicLength = Int(data[idx]) << 8 | Int(data[idx+1])
                        idx += 2 + topicLength
                        if idx <= data.count {
                            let payload = data[idx..<data.count]
                            if let text = String(data: payload, encoding: .utf8) {
                                self?.debugMessagePublisher.send("MQTT message: \(text)")
                                WatchConnectivityManager.shared.send(message: text)
                            }
                        }
                    }
                case .string(let str):
                    self?.debugMessagePublisher.send("Received string message: \(str)")
                @unknown default:
                    self?.debugMessagePublisher.send("Unknown message received")
                }
                // Continue to receive next message
                self?.receiveLoop()
            }
        }
    }

    private func sendMQTTSubscribePacket() {
        func encodeString(_ string: String) -> [UInt8] {
            let utf8 = Array(string.utf8)
            let len = UInt16(utf8.count)
            return [UInt8(len >> 8), UInt8(len & 0xFF)] + utf8
        }

        let packetIdentifier: UInt16 = 1
        let topicFilter = encodeString(topic)
        let payload: [UInt8] = topicFilter + [0x00] // QoS 0
        let identifierBytes: [UInt8] = [UInt8(packetIdentifier >> 8), UInt8(packetIdentifier & 0xFF)]
        let remainingLength = identifierBytes.count + payload.count
        var packet: [UInt8] = [0x82]
        packet += encodeRemainingLength(remainingLength)
        packet += identifierBytes
        packet += payload

        let data = Data(packet)
        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error = error {
                self?.debugMessagePublisher.send("Failed to send MQTT SUBSCRIBE: \(error.localizedDescription)")
            } else {
                self?.debugMessagePublisher.send("MQTT SUBSCRIBE packet sent")
            }
        }
    }
}
