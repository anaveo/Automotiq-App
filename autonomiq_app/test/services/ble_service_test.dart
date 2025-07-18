import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:autonomiq_app/services/ble_service.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBluetoothAdapter mockAdapter;
  late BleService bleService;
  late MockBluetoothDevice mockDevice;
  late MockScanResult mockScanResult;
  late MockPermissionService mockPermissions;

  late StreamController<List<ScanResult>> scanStreamController;

  setUp(() {
    mockAdapter = MockBluetoothAdapter();
    mockDevice = MockBluetoothDevice();
    mockScanResult = MockScanResult();
    mockPermissions = MockPermissionService();
    bleService = BleService(adapter: mockAdapter, permissionService: mockPermissions);

    // Stub permission responses
    when(mockPermissions.bluetoothScanStatus).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.bluetoothConnectStatus).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.locationStatus).thenAnswer((_) async => PermissionStatus.granted);

    when(mockPermissions.requestBluetoothScan()).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.requestBluetoothConnect()).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.requestLocation()).thenAnswer((_) async => PermissionStatus.granted);

    // Stub BLE stream and scan behavior
    scanStreamController = StreamController<List<ScanResult>>.broadcast();
    when(mockAdapter.scanResults).thenAnswer((_) => scanStreamController.stream);

    when(mockAdapter.startScan(timeout: anyNamed('timeout'))).thenAnswer((_) async => null);
    when(mockAdapter.stopScan()).thenAnswer((_) async => null);
  });

  tearDown(() async {
    await scanStreamController.close();
  });

  group('scanForElmDevices', () {
    test('returns ELM/OBD devices', () async {
      final streamController = StreamController<List<ScanResult>>();

      // Stub adapter behavior
      when(mockAdapter.scanResults).thenAnswer((_) => streamController.stream);
      when(mockAdapter.startScan(timeout: anyNamed('timeout')))
          .thenAnswer((_) async {});
      when(mockAdapter.stopScan()).thenAnswer((_) async {});
      when(mockDevice.platformName).thenReturn('VEEPEAK');
      when(mockScanResult.device).thenReturn(mockDevice);

      // Simulate scan results
      final scanFuture = bleService.scanForElmDevices(timeout: Duration(seconds: 1));
      streamController.add([mockScanResult]);

      final devices = await scanFuture;

      // Assertions
      expect(devices.length, 1);
      expect(devices[0], mockDevice);

      // Verifications
      verify(mockAdapter.startScan(timeout: anyNamed('timeout'))).called(1);
      verify(mockAdapter.stopScan()).called(2); // once explicitly, once after timeout
    });

    test('filters non-ELM/OBD devices', () async {
      // Fake device with non-matching name
      when(mockDevice.platformName).thenReturn('JBL-Fetty-Wap');
      when(mockScanResult.device).thenReturn(mockDevice);

      // Simulate scan result before calling the method
      scanStreamController.add([mockScanResult]);

      final devices = await bleService.scanForElmDevices(timeout: Duration(milliseconds: 100));

      // Expect no devices matched
      expect(devices.isEmpty, true);

      // Optional: verify scan start/stop called
      verify(mockAdapter.startScan(timeout: anyNamed('timeout'))).called(1);
      verify(mockAdapter.stopScan()).called(greaterThanOrEqualTo(1));
    });

    test('throws on permission denied', () async {
      when(mockPermissions.bluetoothScanStatus).thenAnswer((_) async => PermissionStatus.denied);
      when(mockPermissions.requestBluetoothScan()).thenAnswer((_) async => PermissionStatus.denied);

      expect(() => bleService.scanForElmDevices(), throwsException);
    });

    test('throws on scan failure', () async {
      when(mockAdapter.startScan(timeout: anyNamed('timeout'))).thenThrow(Exception('Scan error'));
      expect(() => bleService.scanForElmDevices(), throwsException);
    });
  });

  group('connect', () {
    test('connects to device if not connected', () async {
      final streamController = StreamController<BluetoothConnectionState>();
      when(mockDevice.connectionState).thenAnswer((_) => streamController.stream);
      when(mockDevice.connect(timeout: anyNamed('timeout'))).thenAnswer((_) async {});
      streamController.add(BluetoothConnectionState.disconnected);

      await bleService.connect(mockDevice);
      verify(mockDevice.connect(timeout: anyNamed('timeout'))).called(1);
    });

    test('skips connect if already connected', () async {
      final streamController = StreamController<BluetoothConnectionState>();
      when(mockDevice.connectionState).thenAnswer((_) => streamController.stream);
      streamController.add(BluetoothConnectionState.connected);

      await bleService.connect(mockDevice);
      verifyNever(mockDevice.connect(timeout: anyNamed('timeout')));
    });

    test('throws on connection timeout', () async {
      final streamController = StreamController<BluetoothConnectionState>();
      when(mockDevice.connectionState).thenAnswer((_) => streamController.stream);
      // Do not add state to simulate timeout
      expect(() => bleService.connect(mockDevice), throwsA(isA<TimeoutException>()));
    });

    test('throws on connection failure', () async {
      final streamController = StreamController<BluetoothConnectionState>();
      when(mockDevice.connectionState).thenAnswer((_) => streamController.stream);
      when(mockDevice.connect(timeout: anyNamed('timeout'))).thenThrow(Exception('Connection error'));
      streamController.add(BluetoothConnectionState.disconnected);

      expect(() => bleService.connect(mockDevice), throwsException);
    });
  });

  group('disconnect', () {
    test('disconnects if connected', () async {
      final streamController = StreamController<BluetoothConnectionState>();
      when(mockDevice.connectionState).thenAnswer((_) => streamController.stream);
      when(mockDevice.disconnect()).thenAnswer((_) async {});
      streamController.add(BluetoothConnectionState.connected);

      await bleService.disconnect(mockDevice);
      verify(mockDevice.disconnect()).called(1);
    });

    test('skips disconnect if not connected', () async {
      final streamController = StreamController<BluetoothConnectionState>();
      when(mockDevice.connectionState).thenAnswer((_) => streamController.stream);
      streamController.add(BluetoothConnectionState.disconnected);

      await bleService.disconnect(mockDevice);
      verifyNever(mockDevice.disconnect());
    });

    test('throws on disconnection failure', () async {
      final streamController = StreamController<BluetoothConnectionState>();
      when(mockDevice.connectionState).thenAnswer((_) => streamController.stream);
      when(mockDevice.disconnect()).thenThrow(Exception('Disconnect error'));
      streamController.add(BluetoothConnectionState.connected);

      expect(() => bleService.disconnect(mockDevice), throwsException);
    });

    test('throws on disconnection timeout', () async {
      final streamController = StreamController<BluetoothConnectionState>();
      when(mockDevice.connectionState).thenAnswer((_) => streamController.stream);
      // Do not add state to simulate timeout
      expect(() => bleService.disconnect(mockDevice), throwsA(isA<TimeoutException>()));
    });
  });

  group('getDeviceState', () {
    test('returns connection state', () async {
      final streamController = StreamController<BluetoothConnectionState>();
      when(mockDevice.connectionState).thenAnswer((_) => streamController.stream);
      streamController.add(BluetoothConnectionState.connected);

      final state = await bleService.getDeviceState(mockDevice);
      expect(state, BluetoothConnectionState.connected);
    });

    test('throws on timeout', () async {
      when(mockDevice.connectionState).thenAnswer((_) => StreamController<BluetoothConnectionState>().stream);
      expect(() => bleService.getDeviceState(mockDevice), throwsA(isA<TimeoutException>()));
    });
  });

  group('getConnectedDevices', () {
    test('returns connected devices', () async {
      when(mockAdapter.connectedDevices).thenAnswer((_) async => <BluetoothDevice>[mockDevice]);
      final devices = await bleService.getConnectedDevices();
      expect(devices.length, 1);
      expect(devices[0], mockDevice);
    });

    test('throws on failure', () async {
      when(mockAdapter.connectedDevices).thenThrow(Exception('Error fetching devices'));
      expect(() => bleService.getConnectedDevices(), throwsException);
    });
  });

  group('requestPermissions', () {
    test('grants all permissions', () async {
      await bleService.requestPermissions();
      verify(mockPermissions.bluetoothScanStatus).called(1);
      verify(mockPermissions.bluetoothConnectStatus).called(1);
      verify(mockPermissions.locationStatus).called(1);
    });

    test('throws on permission denial', () async {
      when(mockPermissions.bluetoothScanStatus).thenAnswer((_) async => PermissionStatus.denied);
      when(mockPermissions.bluetoothConnectStatus).thenAnswer((_) async => PermissionStatus.denied);
      when(mockPermissions.locationStatus).thenAnswer((_) async => PermissionStatus.denied);

      when(mockPermissions.requestBluetoothScan()).thenAnswer((_) async => PermissionStatus.denied);
      when(mockPermissions.requestBluetoothConnect()).thenAnswer((_) async => PermissionStatus.denied);
      when(mockPermissions.requestLocation()).thenAnswer((_) async => PermissionStatus.denied);

      expect(() => bleService.requestPermissions(), throwsException);
    });
  });
}