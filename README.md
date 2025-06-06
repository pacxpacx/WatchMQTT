Simple watch and phone apps for receiving MQTT messages over a WebSocket connection.

The watch no longer opens its own MQTT connection. Instead the phone app forwards MQTT PUBLISH payloads to the watch using `WatchConnectivity` so the watch can display them when both devices share the same Wi‑Fi network. Messages are queued with `transferUserInfo` when the watch is unreachable.

The phone app still sends proper MQTT `CONNECT` and `SUBSCRIBE` packets after opening the WebSocket so brokers accept the connection. The WebSocket handshake includes `Sec-WebSocket-Protocol: mqtt`.

Use the **Send to Watch** button in the iOS app to push a test message to the watch. Both devices must be paired and on the same Wi‑Fi network for messages to appear.
