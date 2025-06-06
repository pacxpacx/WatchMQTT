Simple watch and phone apps for receiving MQTT messages over a WebSocket connection.

Both apps now send proper MQTT `CONNECT` and `SUBSCRIBE` packets after the socket is opened so brokers will forward messages correctly. The watch UI lets you specify a WebSocket path (default `/ws`) and both apps default to port `80`. Paths lacking the leading slash are automatically fixed and the watch app waits for the broker's `CONNACK` before reporting that it is connected. WebSocket connections include the `Sec-WebSocket-Protocol: mqtt` header so brokers requiring the MQTT subprotocol accept the handshake. A tiny UDP datagram is sent on launch—and again when requesting access—to ensure the local network permission prompt appears even if the connection fails.

When opening a WebSocket on watchOS, the app waits briefly before sending the MQTT CONNECT packet so the socket is fully established.
