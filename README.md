# Automotiq - AI-Powered Vehicle Diagnostics

## Introduction

Automotiq is a comprehensive vehicle diagnostic system. It utilizes on-device AI inference to provide drivers with intelligent vehicle health monitoring and troubleshooting. The app leverages Google's Gemma 3n multimodal AI model to analyze diagnostic trouble codes (DTCs) streamed from an OBD2 dongle via Bluetooth Low Energy (BLE) and provides insights on vehicle faults as well as repair guidance.

## System Overview

Automotiq features a comprehensive vehicle diagnostics platform with the following key capabilities:

- **AI-Powered Diagnostics**: Advanced analysis of diagnostic trouble codes using Gemma 3n
- **Multimodal Chat Interface**: Text and image-based AI assistance for automotive issues
- **OBD2 Integration**: Real-time vehicle data collection via Bluetooth Low Energy
- **Offline Capability**: Local AI processing and diagnostic database

The app supports both demo mode for new users and full OBD2 device integration for comprehensive vehicle monitoring.

## Links

- **Demo Video**: [https://www.youtube.com/watch?v=XCygbZQzIXk](https://www.youtube.com/watch?v=XCygbZQzIXk)
- **Kaggle Page**: [TODO]
- **Technical Writeup**: [Automotiq_Technical_Report.pdf](docs/Automotiq_Technical_Report.pdf)
- **Landing Page**: [automotiq.ai](https://www.automotiq.ai)

## Installation

Currently, the application only supports Android devices. The app has been tested on the following hardware:

- Samsung S25 FE
- Samsung S22 Ultra

If you have installed and tested this app on your device, please send us a message.

**Note**: When the app starts for the first time, the Gemma 3n model is downloaded from the internet. This takes 2-4 minutes. **Please do not close the app or turn off the device while the model is downloading!** This may corrupt the model and cause the app to fail.

### Download APK

1. Download the latest APK from our releases
2. Enable "Install from Unknown Sources" in your Android settings
3. Install the APK file
4. Launch Automotiq and wait for the model to download. Downloading only happens on first-time init.

#### Building for Different Architectures

- **ARM64 (Recommended)**: `flutter build apk --release --target-platform android-arm64`
- **Universal**: `flutter build apk --release`

#### Troubleshooting

- The app is compatible with the VEEPEAK BLE OBD2 scanner. Other devices may not work.
- Grant necessary permissions for Bluetooth, Location, and Camera

## Usage

1. **First Launch**: The app will download the AI model (3-6GB) on first launch
2. **Demo Mode**: New users can explore features in demo mode without OBD2 devices
3. **Device Setup**: Connect your OBD2 device via Bluetooth for full functionality
4. **Diagnostics**: Use the diagnosis screen to analyze trouble codes
5. **AI Chat**: Ask questions or upload images for AI-powered assistance

## Support

For technical support or questions, please refer to our documentation or create an issue in the repository.
