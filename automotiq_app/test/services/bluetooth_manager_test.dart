import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:automotiq_app/services/bluetooth_manager.dart';
import '../mocks.mocks.dart';

void main() {
  late MockBleService mockBleService;
  late MockDiscoveredDevice mockDevice;
  late BluetoothManager bluetoothManager;
  late StreamController<DeviceConnectionState> bleStateController;

  setUp(() {
    mockBleService = MockBleService();
    mockDevice = MockDiscoveredDevice();
    bleStateController = StreamController<DeviceConnectionState>.broadcast();

    // DiscoveredDevice stub
    when(mockDevice.id).thenReturn('VEEPEAK:1234');
    when(mockDevice.name).thenReturn('VEEPEAK');
    when(mockDevice.manufacturerData)
        .thenReturn(Uint8List.fromList([0x01, 0x02]));

    // BleService stubs
    when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
        .thenAnswer((_) async => [mockDevice]);
    when(mockBleService.connectionStateStream)
        .thenAnswer((_) => bleStateController.stream);
    when(mockBleService.getDeviceState())
        .thenReturn(DeviceConnectionState.disconnected);
    when(mockBleService.connectToDevice(any))
        .thenAnswer((_) async {});
    when(mockBleService.disconnectDevice())
        .thenAnswer((_) async {});

    bluetoothManager = BluetoothManager(bleService: mockBleService);
  });

  tearDown(() async {
    await bleStateController.close();
    await bluetoothManager.dispose();
  });

  test('initial state is disconnected', () async {
    final states = <DeviceConnectionState>[];
    final sub = bluetoothManager.connectionStateStream.listen(states.add);

    // allow the constructor-added event to propagate
    await Future.microtask(() {});

    expect(states, [DeviceConnectionState.disconnected]);
    await sub.cancel();
  });

  group('scanForNewObdDevices', () {
    test('filters only VEEPEAK/AUTOMOTIQ names', () async {
      final other = MockDiscoveredDevice();
      when(other.id).thenReturn('OTHER:5678');
      when(other.name).thenReturn('OtherDevice');
      when(other.manufacturerData).thenReturn(Uint8List(0));
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [mockDevice, other]);

      final devices = await bluetoothManager.scanForNewDevices(
        timeout: Duration(seconds: 1),
      );
      expect(devices, hasLength(1));
      expect(devices.first.name, 'VEEPEAK');
    });

    test('returns empty list when none match', () async {
      final other = MockDiscoveredDevice();
      when(other.id).thenReturn('OTHER:5678');
      when(other.name).thenReturn('OtherDevice');
      when(other.manufacturerData).thenReturn(Uint8List(0));
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [other]);

      final devices = await bluetoothManager.scanForNewDevices(
        timeout: Duration(seconds: 1),
      );
      expect(devices, isEmpty);
    });

    test('throws if BLE scan fails', () async {
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenThrow(Exception('Scan failed'));

      expect(
        () => bluetoothManager.scanForNewDevices(timeout: Duration(seconds: 1)),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          'Exception: Failed to scan for new OBD devices: Exception: Scan failed',
        )),
      );
    });
  });

  group('scanForSpecificObdDevice', () {
    const name = 'VEEPEAK';
    final data = Uint8List.fromList([0x01, 0x02]);

    test('finds a matching device', () async {
      final device = await bluetoothManager.scanForSpecificObdDevice(
        expectedName: name,
        expectedManufacturerData: data,
        timeout: Duration(seconds: 1),
      );
      expect(device, isNotNull);
      expect(device!.name, name);
    });

    test('returns null when none match', () async {
      final other = MockDiscoveredDevice();
      when(other.id).thenReturn('OTHER:5678');
      when(other.name).thenReturn('OtherDevice');
      when(other.manufacturerData).thenReturn(Uint8List(0));
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenAnswer((_) async => [other]);

      final device = await bluetoothManager.scanForSpecificObdDevice(
        expectedName: name,
        expectedManufacturerData: data,
        timeout: Duration(seconds: 1),
      );
      expect(device, isNull);
    });

    test('throws if BLE scan fails', () async {
      when(mockBleService.scanForDevices(timeout: anyNamed('timeout')))
          .thenThrow(Exception('Scan failed'));

      expect(
        () => bluetoothManager.scanForSpecificObdDevice(
          expectedName: name,
          expectedManufacturerData: data,
          timeout: Duration(seconds: 1),
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          'Exception: Failed to scan for specific OBD device: Exception: Scan failed',
        )),
      );
    });
  });

  group('connectToDevice', () {
    test('connects and emits connected state', () async {
      when(mockBleService.getDeviceState())
          .thenReturn(DeviceConnectionState.connected);

      final states = <DeviceConnectionState>[];
      final sub = bluetoothManager.connectionStateStream.listen(states.add);

      await bluetoothManager.connectToDevice(mockDevice);
      // drive the BLE-service stream
      bleStateController.add(DeviceConnectionState.connected);
      await Future.microtask(() {});

      expect(bluetoothManager.currentDevice, mockDevice);
      expect(
        states,
        [DeviceConnectionState.disconnected, DeviceConnectionState.connected],
      );
      verify(mockBleService.connectToDevice(mockDevice)).called(1);
      await sub.cancel();
    });

    test('no-op if already connected', () async {
      when(mockBleService.getDeviceState())
          .thenReturn(DeviceConnectionState.connected);
      // first connect
      await bluetoothManager.connectToDevice(mockDevice);
      bleStateController.add(DeviceConnectionState.connected);
      await Future.microtask(() {});

      final states = <DeviceConnectionState>[];
      final sub = bluetoothManager.connectionStateStream.listen(states.add);

      // redundant connect
      await bluetoothManager.connectToDevice(mockDevice);
      await Future.microtask(() {});

      expect(states, [DeviceConnectionState.connected]);
      verify(mockBleService.connectToDevice(mockDevice)).called(1);
      await sub.cancel();
    });

    test('auto-reconnects on unexpected disconnect', () async {
      when(mockBleService.getDeviceState())
          .thenReturn(DeviceConnectionState.connected);
      when(mockBleService.connectToDevice(mockDevice))
          .thenAnswer((_) async {});

      final states = <DeviceConnectionState>[];
      final sub = bluetoothManager.connectionStateStream.listen(states.add);

      await bluetoothManager.connectToDevice(mockDevice, autoReconnect: true);
      bleStateController.add(DeviceConnectionState.disconnected);
      await Future.microtask(() {});

      // simulate reconnection attempt
      bleStateController.add(DeviceConnectionState.connecting);
      await Future.microtask(() {});

      expect(states, [
        DeviceConnectionState.disconnected, // initial
        DeviceConnectionState.disconnected, // after disconnect
        DeviceConnectionState.connecting,   // auto-reconnect
      ]);
      verify(mockBleService.connectToDevice(mockDevice)).called(2);
      await sub.cancel();
    });

    test('throws if the BLE-service connection fails', () async {
      when(mockBleService.connectToDevice(any))
          .thenThrow(Exception('Connection failed'));

      expect(
        () => bluetoothManager.connectToDevice(mockDevice),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          'Exception: Failed to connect to device: Exception: Connection failed',
        )),
      );
      // ensure we clear the device on error
      bleStateController.add(DeviceConnectionState.disconnected);
      await Future.microtask(() {});
      expect(bluetoothManager.currentDevice, isNull);
    });
  });

  group('disconnectDevice', () {
    test('disconnects and emits disconnected', () async {
      when(mockBleService.getDeviceState())
          .thenReturn(DeviceConnectionState.connected);
      await bluetoothManager.connectToDevice(mockDevice);
      bleStateController.add(DeviceConnectionState.connected);
      await Future.microtask(() {});

      final states = <DeviceConnectionState>[];
      final sub = bluetoothManager.connectionStateStream.listen(states.add);

      await bluetoothManager.disconnectDevice();
      bleStateController.add(DeviceConnectionState.disconnected);
      await Future.microtask(() {});

      expect(bluetoothManager.currentDevice, isNull);
      expect(states, [
        DeviceConnectionState.connected,
        DeviceConnectionState.disconnected,
      ]);
      verify(mockBleService.disconnectDevice()).called(1);
      await sub.cancel();
    });

    test('throws if BLE-service disconnect fails', () async {
      when(mockBleService.getDeviceState())
          .thenReturn(DeviceConnectionState.connected);
      await bluetoothManager.connectToDevice(mockDevice);
      bleStateController.add(DeviceConnectionState.connected);
      await Future.microtask(() {});

      when(mockBleService.disconnectDevice())
          .thenThrow(Exception('Disconnect failed'));

      expect(
        () => bluetoothManager.disconnectDevice(),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          'Exception: Failed to disconnect device: Exception: Disconnect failed',
        )),
      );
      bleStateController.add(DeviceConnectionState.disconnected);
      await Future.microtask(() {});
      expect(bluetoothManager.currentDevice, isNull);
    });
  });

  group('dispose', () {
    test('cleans up and stops listening', () async {
      when(mockBleService.getDeviceState())
          .thenReturn(DeviceConnectionState.connected);
      await bluetoothManager.connectToDevice(mockDevice);
      bleStateController.add(DeviceConnectionState.connected);
      await Future.microtask(() {});

      await bluetoothManager.dispose();
      // after disposal, further BLE events are dropped
      bleStateController.add(DeviceConnectionState.disconnected);
      await Future.microtask(() {});

      expect(bluetoothManager.currentDevice, isNull);
      verify(mockBleService.disconnectDevice()).called(1);
    });

    test('throws if dispose fails', () async {
      when(mockBleService.getDeviceState())
          .thenReturn(DeviceConnectionState.connected);
      await bluetoothManager.connectToDevice(mockDevice);
      bleStateController.add(DeviceConnectionState.connected);
      await Future.microtask(() {});

      when(mockBleService.disconnectDevice())
          .thenThrow(Exception('Dispose failed'));

      expect(
        () => bluetoothManager.dispose(),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          'Exception: Failed to dispose BluetoothManager: Exception: Dispose failed',
        )),
      );
      // still end up with no current device
      bleStateController.add(DeviceConnectionState.disconnected);
      await Future.microtask(() {});
      expect(bluetoothManager.currentDevice, isNull);
    });
  });
}
