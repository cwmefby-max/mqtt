
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MQTTService with ChangeNotifier {
  MqttServerClient? _client;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  Future<void> connect(String server, String clientIdentifier) async {
    _client = MqttServerClient(server, clientIdentifier);
    _client!.port = 1883;
    _client!.logging(on: true);
    _client!.onConnected = onConnected;
    _client!.onDisconnected = onDisconnected;
    _client!.onUnsubscribed = onUnsubscribed;
    _client!.onSubscribed = onSubscribed;
    _client!.onSubscribeFail = onSubscribeFail;
    _client!.pongCallback = pong;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMess;

    try {
      await _client!.connect();
    } catch (e) {
      print('Exception: $e');
      disconnect();
    }
  }

  void disconnect() {
    _client?.disconnect();
  }

  void publish(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    _client?.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void onConnected() {
    _isConnected = true;
    notifyListeners();
    print('Connected');
  }

  void onDisconnected() {
    _isConnected = false;
    notifyListeners();
    print('Disconnected');
  }

  void onSubscribed(String topic) {
    print('Subscribed to topic: $topic');
  }

  void onSubscribeFail(String topic) {
    print('Failed to subscribe to topic: $topic');
  }

  void onUnsubscribed(String? topic) {
    print('Unsubscribed from topic: $topic');
  }

  void pong() {
    print('Ping response client callback invoked');
  }
}
