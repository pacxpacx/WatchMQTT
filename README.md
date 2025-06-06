Simple watch and phone apps for receiving MQTT messages over a WebSocket connection.

The watch no longer opens its own MQTT connection. Instead the phone app forwards any MQTT PUBLISH payloads it receives to the watch with `WatchConnectivity` so the watch can display them when both devices share the same Wi‑Fi network.

The phone app still sends proper MQTT `CONNECT` and `SUBSCRIBE` packets after opening the WebSocket so brokers accept the connection. The WebSocket handshake includes `Sec-WebSocket-Protocol: mqtt`.

Use the new **Send Test** button in the iOS app to verify that watch connectivity is working. The button sends a short message to the watch even if no MQTT data has been received.
