# Project Blueprint

## Overview

This document outlines the plan and progress of a Flutter application for IoT testing using the MQTT protocol. The application will allow users to control devices, such as lamps and fans, connected to an ESP32 via an MQTT broker.

## Implemented Features

*   **UI:**
    *   A simple and intuitive user interface with toggle switches for controlling a lamp and a fan.
    *   A status indicator to show the MQTT connection status (Connected/Disconnected).
    *   A button to manually connect or disconnect from the MQTT broker.
*   **MQTT Integration:**
    *   The application uses the `mqtt_client` package to handle MQTT communication.
    *   The `provider` package is used for state management of the MQTT service.
    *   The application connects to a public Mosquitto test broker (`test.mosquitto.org`).
    *   The application publishes messages to the topics `iot/lamp` and `iot/fan` with the payloads "ON" or "OFF" to control the respective devices.

## Current Plan

The current focus is on creating a basic but functional application that can be easily tested and deployed. The following steps have been completed:

1.  **Project Setup:**
    *   Added the `mqtt_client` and `provider` packages to the `pubspec.yaml` file.
2.  **MQTT Service:**
    *   Created an `MQTTService` class to encapsulate the MQTT client logic, including connecting, disconnecting, and publishing messages.
3.  **UI Implementation:**
    *   Designed the `HomePage` widget with switches for the lamp and fan, and a status display for the MQTT connection.
4.  **State Management:**
    *   Integrated the `MQTTService` with the UI using the `provider` package to manage the connection state.
5.  **Main Application:**
    *   Updated the `main.dart` file to initialize the `MQTTService` and launch the `HomePage`.
