import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:autonomiq_app/services/ble_service.dart';
import 'package:autonomiq_app/services/bluetooth_manager.dart';
import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBleService mockBleService;
  late BluetoothManager bluetoothManager;
  late MockBluetoothDevice mockDevice;
  late MockScanResult mockScanResult;
  late StreamController<BluetoothConnectionState> stateStreamController;

  setUp(() {
    mockBleService = MockBleService();
    mockDevice = MockBluetoothDevice();
    mockScanResult = MockScanResult();
    bluetoothManager = BluetoothManager(bleService: mockBleService);

    // Stub device state behavior
    stateStreamController = StreamController<BluetoothConnectionState>.broadcast();
    when(mockDevice.connectionState).thenAnswer((_) => stateStreamController.stream);
  });

  tearDown(() async {
    await stateStreamController.close();
  });

  group('scanForElmDevices', () {
    test('returns ELM/OBD devices', () async {
      when(mockDevice.platformName).thenReturn('VEEPEAK');
      when(mockScanResult.device).thenReturn(mockDevice);
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [mockDevice]);

      final devices = await bluetoothManager.scanForElmDevices(timeout: Duration(seconds: 1));

      expect(devices.length, 1);
      expect(devices[0], mockDevice);
      verify(mockBleService.scanForDevices(timeout: anyNamed('timeout'))).called(1);
    });

    test('filters non-ELM/OBD devices', () async {
      when(mockDevice.platformName).thenReturn('JBL-Fetty-Wap');
      when(mockScanResult.device).thenReturn(mockDevice);
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
      when(mockDevice.id).thenReturn(DeviceIdentifier('TEST_DEVICE_ID'));
      when(mockBleService.reconnectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async => mockDevice);
      stateStreamController.add(BluetoothConnectionState.connected);

      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');

      expect(bluetoothManager.getCurrentDevice(), mockDevice);
      verify(mockBleService.reconnectToDevice('TEST_DEVICE_ID')).called(1);
    });

    test('skips if same device ID', () async {
      when(mockDevice.id).thenReturn(DeviceIdentifier('TEST_DEVICE_ID'));
      when(mockBleService.reconnectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async => mockDevice);
      stateStreamController.add(BluetoothConnectionState.connected);

      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');
      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');

      verify(mockBleService.reconnectToDevice('TEST_DEVICE_ID')).called(1);
    });

    test('throws on initialization failure', () async {
      when(mockBleService.reconnectToDevice('TEST_DEVICE_ID')).thenThrow(Exception('Reconnect error'));

      expect(() => bluetoothManager.initializeDevice('TEST_DEVICE_ID'), throwsException);
    });
  });

  group('getConnectionStateStream', () {
    test('streams connection state', () async {
      when(mockDevice.id).thenReturn(DeviceIdentifier('TEST_DEVICE_ID'));
      when(mockBleService.reconnectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async => mockDevice);

      // Initialize device
      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');

      // Subscribe to stream and collect states
      final stream = bluetoothManager.getConnectionStateStream();
      final states = <BluetoothConnectionState>[];
      final subscription = stream.listen(states.add);

      // Emit states after subscription
      stateStreamController.add(BluetoothConnectionState.connected);
      await Future.delayed(Duration(milliseconds: 100)); // Wait for first state
      stateStreamController.add(BluetoothConnectionState.disconnected);
      await Future.delayed(Duration(milliseconds: 100)); // Wait for second state

      // Simulate auto-reconnect
      when(mockBleService.reconnectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async {
        stateStreamController.add(BluetoothConnectionState.connected); // Simulate reconnect
        return mockDevice;
      });

      await Future.delayed(Duration(milliseconds: 200)); // Wait for auto-reconnect
      await subscription.cancel();

      expect(states, [
        BluetoothConnectionState.connected,
        BluetoothConnectionState.disconnected,
        BluetoothConnectionState.connected,
      ]);
    });

    test('throws if no device initialized', () async {
      expect(() => bluetoothManager.getConnectionStateStream(), throwsException);
    });
  });

  group('disconnectDevice', () {
    test('disconnects and cleans up', () async {
      when(mockDevice.id).thenReturn(DeviceIdentifier('TEST_DEVICE_ID'));
      when(mockBleService.reconnectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async => mockDevice);
      when(mockBleService.disconnect(mockDevice)).thenAnswer((_) async {});
      stateStreamController.add(BluetoothConnectionState.connected);

      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');
      await bluetoothManager.disconnectDevice();

      expect(bluetoothManager.getCurrentDevice(), null);
      verify(mockBleService.disconnect(mockDevice)).called(1);
    });

    test('throws on disconnect failure', () async {
      when(mockDevice.id).thenReturn(DeviceIdentifier('TEST_DEVICE_ID'));
      when(mockBleService.reconnectToDevice('TEST_DEVICE_ID')).thenAnswer((_) async => mockDevice);
      when(mockBleService.disconnect(mockDevice)).thenThrow(Exception('Disconnect error'));

      await bluetoothManager.initializeDevice('TEST_DEVICE_ID');
      expect(() => bluetoothManager.disconnectDevice(), throwsException);
    });
  });
}