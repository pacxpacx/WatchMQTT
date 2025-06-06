//
//  MQTTWebSocketClient.swift
//  WatchMQTT
//
//  Created by Pavel Cintins on 27/05/2025.
//



import Foundation

protocol MQTTWebSocketClientDelegate: AnyObject {
    func mqttClientDidConnect(_ client: MQTTWebSocketClient)
    func mqttClient(_ client: MQTTWebSocketClient, didReceiveMessage message: String)
    func mqttClientDidDisconnect(_ client: MQTTWebSocketClient)
}

class MQTTWebSocketClient: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let url: URL
    private let clientId: String
    private let username: String
    private let password: String
    private var topic: String
    weak var delegate: MQTTWebSocketClientDelegate?

    // Encode MQTT remaining length using the variable-length format
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

    init(url: URL, clientId: String, username: String, password: String, topic: String) {
        self.url = url
        self.clientId = clientId
        self.username = username
        self.password = password
        self.topic = topic
        super.init()
    }

    func updateTopic(_ newTopic: String) {
        self.topic = newTopic

        // Prepare and send a new SUBSCRIBE packet for the new topic
        let packetIdentifier: UInt16 = 1

        func mqttString(_ string: String) -> [UInt8] {
            let utf8 = Array(string.utf8)
            let len = UInt16(utf8.count)
            return [UInt8(len >> 8), UInt8(len & 0xFF)] + utf8
        }

        let topicFilter = mqttString(newTopic)
        let subscribePayload: [UInt8] = topicFilter + [0x00] // QoS 0
        let subscribePacketIdentifier: [UInt8] = [UInt8(packetIdentifier >> 8), UInt8(packetIdentifier & 0xFF)]
        let subscribeRemainingLength = subscribePacketIdentifier.count + subscribePayload.count
        let subscribeFixedHeader: [UInt8] = [0x82] + encodeRemainingLength(subscribeRemainingLength)
        let subscribePacket = subscribeFixedHeader + subscribePacketIdentifier + subscribePayload

        self.webSocketTask?.send(.data(Data(subscribePacket))) { error in
            if let error = error {
                print("Failed to send SUBSCRIBE packet for topic \(newTopic): \(error)")
            } else {
                print("Updated topic and sent SUBSCRIBE for \(newTopic)")
            }
        }
    }

    func connect() {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        var request = URLRequest(url: url)
        // Set MQTT subprotocol so brokers accept this WebSocket for MQTT traffic
        request.addValue("mqtt", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receive()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
    }

    private func receive() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("WebSocket receive failed: \(error)")
            case .success(let message):
                switch message {
                case .string(let text):
                    self.delegate?.mqttClient(self, didReceiveMessage: text)
                default:
                    break
                }
            }
            self.receive()
        }
    }
    
    func sendConnectAndSubscribe() {
        let clientId = self.clientId
        let username = self.username
        let password = self.password
        let topic = self.topic
        let packetIdentifier: UInt16 = 1

        func mqttString(_ string: String) -> [UInt8] {
            let utf8 = Array(string.utf8)
            let len = UInt16(utf8.count)
            return [UInt8(len >> 8), UInt8(len & 0xFF)] + utf8
        }

        var connectVariableHeader: [UInt8] = []
        connectVariableHeader += mqttString("MQTT") // Protocol Name
        connectVariableHeader += [0x04] // Protocol Level 4
        connectVariableHeader += [0xC2] // Connect Flags: username+password+clean session
        connectVariableHeader += [0x00, 0x3C] // Keep Alive 60s

        var connectPayload: [UInt8] = []
        connectPayload += mqttString(clientId)
        connectPayload += mqttString(username)
        connectPayload += mqttString(password)

        let connectRemainingLength = connectVariableHeader.count + connectPayload.count
        let connectFixedHeader: [UInt8] = [0x10] + encodeRemainingLength(connectRemainingLength)
        let connectPacket = connectFixedHeader + connectVariableHeader + connectPayload

        // SUBSCRIBE Packet (to topic "home/button", QoS 0)
        let topicFilter = mqttString(topic)
        let subscribePayload: [UInt8] = topicFilter + [0x00] // QoS 0
        let subscribePacketIdentifier: [UInt8] = [UInt8(packetIdentifier >> 8), UInt8(packetIdentifier & 0xFF)]
        let subscribeRemainingLength = subscribePacketIdentifier.count + subscribePayload.count
        let subscribeFixedHeader: [UInt8] = [0x82] + encodeRemainingLength(subscribeRemainingLength)
        let subscribePacket = subscribeFixedHeader + subscribePacketIdentifier + subscribePayload

        // Send CONNECT
        webSocketTask?.send(.data(Data(connectPacket))) { error in
            if let error = error {
                print("Failed to send CONNECT packet: \(error)")
            } else {
                print("CONNECT packet sent")
            }
        }

        // Send SUBSCRIBE (with short delay to allow CONNECT)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.webSocketTask?.send(.data(Data(subscribePacket))) { error in
                if let error = error {
                    print("Failed to send SUBSCRIBE packet: \(error)")
                } else {
                    print("SUBSCRIBE packet sent")
                }
            }
        }
    }
}

extension MQTTWebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        delegate?.mqttClientDidConnect(self)
        sendConnectAndSubscribe()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        delegate?.mqttClientDidDisconnect(self)
    }
}

