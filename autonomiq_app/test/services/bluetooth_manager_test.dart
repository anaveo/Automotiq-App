import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:autonomiq_app/services/bluetooth_manager.dart';
import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBleService mockBleService;
  late BluetoothManager bluetoothManager;
  late MockDiscoveredDevice mockDevice;
  late StreamController<DeviceConnectionState> stateStreamController;

  setUp(() {
    mockBleService = MockBleService();
    mockDevice = MockDiscoveredDevice();
    bluetoothManager = BluetoothManager(bleService: mockBleService);

    // Stub device state behavior
    stateStreamController = StreamController<DeviceConnectionState>.broadcast();
    when(mockBleService.getDeviceStateStream(any)).thenAnswer((_) => stateStreamController.stream);
  });

  tearDown(() async {
    await stateStreamController.close();
  });

  group('scanForElmDevices', () {
    test('returns ELM/OBD devices', () async {
      when(mockDevice.name).thenReturn('VEEPEAK');
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [mockDevice]);

      final devices = await bluetoothManager.scanForElmDevices(timeout: Duration(seconds: 1));

      expect(devices.length, 1);
      expect(devices[0], mockDevice);
      verify(mockBleService.scanForDevices(timeout: anyNamed('timeout'))).called(1);
    });

    test('filters non-ELM/OBD devices', () async {
      when(mockDevice.name).thenReturn('JBL-Fetty-Wap');
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [mockDevice]);

      final devices = await bluetoothManager.scanForElmDevices(timeout: Duration(seconds: 1));

      expect(devices.isEmpty, true);
      verify(mockBleService.scanForDevices(timeout: anyNamed('timeout'))).called(1);
    });

    test('returns empty list if no devices found', () async {
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => []);

      final devices = await bluetoothManager.scanForElmDevices(timeout: Duration(seconds: 1));

      expect(devices.isEmpty, true);
      verify(mockBleService.scanForDevices(timeout: anyNamed('timeout'))).called(1);
    });

    test('throws on scan failure', () async {
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenThrow(Exception('Scan error'));

      expect(() => bluetoothManager.scanForElmDevices(timeout: Duration(seconds: 1)), throwsException);
    });
  });

  group('initializeDevice', () {
    test('initializes device and sets up state stream', () async {
      when(mockDevice.id).thenReturn('TEST_DEVICE_ID');
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [mockDevice]);
      when(mockBleService.connectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async {});
      stateStreamController.add(DeviceConnectionState.connected);

      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');

      expect(bluetoothManager.getCurrentDevice(), mockDevice);
      verify(mockBleService.connectToDevice('TEST_DEVICE_ID')).called(1);
    });

    test('skips if same device ID', () async {
      when(mockDevice.id).thenReturn('TEST_DEVICE_ID');
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [mockDevice]);
      when(mockBleService.connectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async {});
      stateStreamController.add(DeviceConnectionState.connected);

      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');
      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');

      verify(mockBleService.connectToDevice('TEST_DEVICE_ID')).called(1);
    });

    test('throws on initialization failure', () async {
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [mockDevice]);
      when(mockBleService.connectToDevice('TEST_DEVICE_ID')).thenThrow(Exception('Connect error'));

      expect(() => bluetoothManager.initializeDevice('TEST_DEVICE_ID'), throwsException);
    });
  });

  group('getConnectionStateStream', () {
    test('streams connection state', () async {
      when(mockDevice.id).thenReturn('TEST_DEVICE_ID');
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [mockDevice]);
      when(mockBleService.connectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async {});

      // Initialize device
      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');

      // Subscribe to stream and collect states
      final stream = bluetoothManager.getConnectionStateStream();
      final states = <DeviceConnectionState>[];
      final subscription = stream.listen(states.add);

      // Emit states after subscription
      stateStreamController.add(DeviceConnectionState.connected);
      await Future.delayed(Duration(milliseconds: 100));
      stateStreamController.add(DeviceConnectionState.disconnected);
      await Future.delayed(Duration(milliseconds: 100));

      // Simulate auto-reconnect
      when(mockBleService.connectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async {
        stateStreamController.add(DeviceConnectionState.connected);
        when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
            .thenAnswer((_) async => [mockDevice]);
      });

      await Future.delayed(Duration(milliseconds: 200));
      await subscription.cancel();

      expect(states, [
        DeviceConnectionState.connected,
        DeviceConnectionState.disconnected,
        DeviceConnectionState.connected,
      ]);
    });

    test('throws if no device initialized', () async {
      expect(() => bluetoothManager.getConnectionStateStream(), throwsException);
    });
  });

  group('disconnectDevice', () {
    test('disconnects and cleans up', () async {
      when(mockDevice.id).thenReturn('TEST_DEVICE_ID');
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [mockDevice]);
      when(mockBleService.connectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async {});
      when(mockBleService.disconnectDevice('TEST_DEVICE_ID')).thenAnswer((_) async {});
      stateStreamController.add(DeviceConnectionState.connected);

      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');
      await bluetoothManager.disconnectDevice();

      expect(bluetoothManager.getCurrentDevice(), null);
      verify(mockBleService.disconnectDevice('TEST_DEVICE_ID')).called(1);
    });

    test('throws on disconnect failure', () async {
      when(mockDevice.id).thenReturn('TEST_DEVICE_ID');
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [mockDevice]);
      when(mockBleService.connectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async {});
      when(mockBleService.disconnectDevice('TEST_DEVICE_ID')).thenThrow(Exception('Disconnect error'));

      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');
      expect(() => bluetoothManager.disconnectDevice(), throwsException);
    });
  });
}