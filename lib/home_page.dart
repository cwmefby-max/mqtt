
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'mqtt_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _lampState = false;
  bool _fanState = false;

  @override
  Widget build(BuildContext context) {
    final mqttService = Provider.of<MQTTService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('IoT MQTT Control'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Lamp', style: TextStyle(fontSize: 20)),
                Switch(
                  value: _lampState,
                  onChanged: (value) {
                    setState(() {
                      _lampState = value;
                    });
                    if (mqttService.isConnected) {
                      mqttService.publish('iot/lamp', value ? 'ON' : 'OFF');
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Fan', style: TextStyle(fontSize: 20)),
                Switch(
                  value: _fanState,
                  onChanged: (value) {
                    setState(() {
                      _fanState = value;
                    });
                    if (mqttService.isConnected) {
                      mqttService.publish('iot/fan', value ? 'ON' : 'OFF');
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 40),
            Consumer<MQTTService>(
              builder: (context, mqttService, child) {
                return Column(
                  children: [
                    Text(
                      'MQTT Status: ${mqttService.isConnected ? 'Connected' : 'Disconnected'}',
                      style: TextStyle(
                        fontSize: 18,
                        color: mqttService.isConnected ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        if (!mqttService.isConnected) {
                          // Replace with your MQTT broker address and a unique client ID
                          mqttService.connect('test.mosquitto.org', 'flutter_client');
                        } else {
                          mqttService.disconnect();
                        }
                      },
                      child: Text(mqttService.isConnected ? 'Disconnect' : 'Connect'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
