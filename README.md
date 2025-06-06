Simple watch and phone apps for receiving MQTT messages over a WebSocket connection.

The watch app no longer performs any network operations. It simply displays messages it receives from the iPhone companion over `WatchConnectivity`. The phone is responsible for the actual MQTT WebSocket connection and forwards every PUBLISH payload to the watch. When the watch is unreachable these payloads are queued with `transferUserInfo` so nothing is lost.

The phone app still sends proper MQTT `CONNECT` and `SUBSCRIBE` packets after opening the WebSocket so brokers accept the connection. The WebSocket handshake includes `Sec-WebSocket-Protocol: mqtt`.

Use the **Send to Watch** button in the iOS app to push a test message to the watch. Ensure the watch and phone are paired, both apps are running, and both devices share the same Wi‑Fi network for messages to appear.
