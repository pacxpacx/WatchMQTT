Simple watch and phone apps for receiving MQTT messages over a WebSocket connection.

Both apps now send proper MQTT `CONNECT` and `SUBSCRIBE` packets after the socket is opened so brokers will forward messages correctly. The watch UI now lets you specify a WebSocket path when connecting. The watch app also waits for the broker's `CONNACK` before reporting that it is connected.
