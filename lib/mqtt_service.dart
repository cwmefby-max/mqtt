import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MQTTService with ChangeNotifier {
  MqttServerClient? _client;
  bool _isConnected = false;
  bool _isDeviceOnline = false; // Status ESP32

  String _statusPower = "OFF";

  bool get isConnected => _isConnected;
  bool get isDeviceOnline => _isDeviceOnline;
  String get statusPower => _statusPower;

  Timer? _heartbeatTimer;

  Future<void> connect(String server, String clientIdentifier) async {
    _client = MqttServerClient(server, clientIdentifier);
    _client!.port = 1883;
    _client!.logging(on: false);

    _client!.keepAlivePeriod = 20;
    _client!.autoReconnect = true;
    _client!.resubscribeOnAutoReconnect = true;

    _client!.onConnected = onConnected;
    _client!.onDisconnected = onDisconnected;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMess;

    try {
      await _client!.connect();
      await _loadLastStatus();

      _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final MqttPublishMessage recMess = c![0].payload as MqttPublishMessage;
        final String payload = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );
        final String topic = c[0].topic;

        // Daftar semua topik status yang akan diperhatikan
        final List<String> statusTopics = [
          'iot/status/power',
          'iot/status/alarm',
          'iot/status/seat',
          'iot/status/fuel',
          'iot/status/starter',
        ];

        // Jika topik yang masuk adalah salah satu dari topik status di atas
        if (statusTopics.contains(topic)) {
          // Perbarui status dan simpan
          _statusPower = payload;
          _saveLastStatus('lastStatus', payload);
        }

        // Logika untuk status online/offline device
        if (topic == 'iot/status/device' && payload == 'ONLINE') {
          _isDeviceOnline = true;
          _heartbeatTimer?.cancel();
          _heartbeatTimer = Timer(Duration(seconds: 15), () {
            _isDeviceOnline = false;
            notifyListeners();
          });
        }
        notifyListeners();
      });
    } catch (e) {
      disconnect();
    }
  }

  Future<void> _loadLastStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _statusPower = prefs.getString('lastStatus') ?? "OFF";
    notifyListeners();
  }

  Future<void> _saveLastStatus(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(key, value);
  }

  void disconnect() {
    _client?.disconnect();
  }

  void publish(String topic, String message) {
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      _client?.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    }
  }

  void onConnected() {
    _isConnected = true;
    // Subscribe ke semua topik status dan device
    _client!.subscribe('iot/status/device', MqttQos.atLeastOnce);
    _client!.subscribe('iot/status/power', MqttQos.atLeastOnce);
    _client!.subscribe('iot/status/alarm', MqttQos.atLeastOnce);
    _client!.subscribe('iot/status/seat', MqttQos.atLeastOnce);
    _client!.subscribe('iot/status/fuel', MqttQos.atLeastOnce);
    _client!.subscribe('iot/status/starter', MqttQos.atLeastOnce);
    notifyListeners();
  }

  void onDisconnected() {
    _isConnected = false;
    _isDeviceOnline = false;
    notifyListeners();
  }
}
