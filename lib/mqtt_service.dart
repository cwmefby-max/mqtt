import 'dart:async'; // Tambahkan ini untuk Timer
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MQTTService with ChangeNotifier {
  MqttServerClient? _client;
  bool _isConnected = false;
  bool _isDeviceOnline = false; // Status ESP32

  // Status variabel untuk perintah terakhir
  String _statusPower = "OFF";
  
  bool get isConnected => _isConnected;
  bool get isDeviceOnline => _isDeviceOnline;
  String get statusPower => _statusPower;

  Timer? _heartbeatTimer; // Timer untuk deteksi ESP32 Offline

  Future<void> connect(String server, String clientIdentifier) async {
    _client = MqttServerClient(server, clientIdentifier);
    _client!.port = 1883;
    _client!.logging(on: false);
    
    // PENGATURAN STABILITAS ANDROID
    _client!.keepAlivePeriod = 20; 
    _client!.autoReconnect = true;
    _client!.resubscribeOnAutoReconnect = true;

    _client!.onConnected = onConnected;
    _client!.onDisconnected = onDisconnected;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .startClean() // Ubah ke false jika ingin pesan yang terlewat tetap terkirim saat reconnect
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMess;

    try {
      await _client!.connect();
      
      // Listener Data Masuk
      _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final MqttPublishMessage recMess = c![0].payload as MqttPublishMessage;
        final String payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final String topic = c[0].topic;

        // Logika Status Perintah
        if (topic == 'iot/status/power') _statusPower = payload;

        // Logika Status Device (ESP32 ONLINE)
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
      print('Exception: $e');
      disconnect();
    }
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
    // Subscribe otomatis ke semua topik
    _client!.subscribe('iot/status/power', MqttQos.atLeastOnce);
    _client!.subscribe('iot/status/device', MqttQos.atLeastOnce);
    notifyListeners();
  }

  void onDisconnected() {
    _isConnected = false;
    _isDeviceOnline = false; // Jika koneksi putus, anggap device offline
    notifyListeners();
  }
  
  // ... (Fungsi onSubscribed dll tetap ada seperti sebelumnya)
}
