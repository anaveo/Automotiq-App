import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:autonomiq_app/services/ble_service.dart';
import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBluetoothAdapter mockAdapter;
  late BleService bleService;
  late MockPermissionService mockPermissions;
  late StreamController<DiscoveredDevice> scanStreamController;
  late StreamController<ConnectionStateUpdate> connectionStreamController;
  late QualifiedCharacteristic mockCharacteristic;

  setUp(() {
    mockAdapter = MockBluetoothAdapter();
    mockPermissions = MockPermissionService();
    bleService = BleService(adapter: mockAdapter, permissionService: mockPermissions);

    // Stub permission responses
    when(mockPermissions.bluetoothScanStatus).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.bluetoothConnectStatus).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.locationStatus).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.requestBluetoothScan()).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.requestBluetoothConnect()).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.requestLocation()).thenAnswer((_) async => PermissionStatus.granted);

    // Setup mock characteristic
    mockCharacteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse('0000FFE0-0000-1000-8000-00805F9B34FB'),
      characteristicId: Uuid.parse('0000FFE1-0000-1000-8000-00805F9B34FB'),
      deviceId: 'VEEPEAK:1234',
    );

    // Stub BLE streams
    scanStreamController = StreamController<DiscoveredDevice>.broadcast();
    connectionStreamController = StreamController<ConnectionStateUpdate>.broadcast();
    when(mockAdapter.scanForDevices(withServices: anyNamed('withServices')))
        .thenAnswer((_) => scanStreamController.stream);
    when(mockAdapter.getConnectionStateStream(any)).thenAnswer((_) => connectionStreamController.stream);
  });

  tearDown(() async {
    await scanStreamController.close();
    await connectionStreamController.close();
  });

  group('scanForDevices', () {
    test('returns devices', () async {
      // Ensure mockDevice is properly initialized
      final mockDevice = MockDiscoveredDevice();
      when(mockDevice.id).thenReturn('VEEPEAK:1234');
      when(mockDevice.name).thenReturn('VEEPEAK');
      when(mockAdapter.scanForDevices(withServices: anyNamed('withServices')))
          .thenAnswer((_) => Stream.fromIterable([mockDevice]));

      // Start scanning
      final scanFuture = bleService.scanForDevices(timeout: Duration(milliseconds: 100));
      await Future.delayed(Duration(milliseconds: 110)); // Wait for scan completion

      final devices = await scanFuture;

      expect(devices.length, 1);
      expect(devices[0].id, 'VEEPEAK:1234');
      expect(devices[0].name, 'VEEPEAK');
    });

    test('throws on permission denied', () async {
      when(mockPermissions.bluetoothScanStatus).thenAnswer((_) async => PermissionStatus.denied);
      when(mockPermissions.requestBluetoothScan()).thenAnswer((_) async => PermissionStatus.denied);

      expect(() => bleService.scanForDevices(), throwsException);
    });

    test('throws on scan failure', () async {
      when(mockAdapter.scanForDevices(withServices: anyNamed('withServices')))
          .thenThrow(Exception('Scan error'));
      expect(() => bleService.scanForDevices(), throwsException);
    });
  });

  group('connectToDevice', () {
    test('connects to device', () async {
      when(mockAdapter.connectToDevice(any)).thenAnswer((_) async {
        connectionStreamController.add(ConnectionStateUpdate(
          deviceId: 'VEEPEAK:1234',
          connectionState: DeviceConnectionState.connected,
          failure: null,
        ));
      });

      await bleService.connectToDevice('VEEPEAK:1234');
      verify(mockAdapter.connectToDevice('VEEPEAK:1234')).called(1);
    });

    test('throws on connection timeout', () async {
      when(mockAdapter.connectToDevice(any)).thenAnswer((_) => Future.delayed(
            Duration(seconds: 10), // Longer than the 5-second timeout in connectToDevice
            () => throw TimeoutException('Simulated connection timeout'),
          ));

      expect(
        () => bleService.connectToDevice('VEEPEAK:1234'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to connect to device: TimeoutException: Connection timeout for device: VEEPEAK:1234',
          ),
        ),
      );
    });

    test('throws on connection failure', () async {
      when(mockAdapter.connectToDevice(any)).thenThrow(Exception('Connection error'));

      expect(() => bleService.connectToDevice('VEEPEAK:1234'), throwsException);
    });
  });

  group('disconnectDevice', () {
    test('disconnects device', () async {
      when(mockAdapter.disconnectDevice(any)).thenAnswer((_) async {
        connectionStreamController.add(ConnectionStateUpdate(
          deviceId: 'VEEPEAK:1234',
          connectionState: DeviceConnectionState.disconnected,
          failure: null,
        ));
      });

      await bleService.disconnectDevice('VEEPEAK:1234');
      verify(mockAdapter.disconnectDevice('VEEPEAK:1234')).called(1);
    });

    test('throws on disconnection timeout', () async {
      when(mockAdapter.disconnectDevice(any)).thenAnswer((_) => Future.delayed(
            Duration(seconds: 10), // Longer than the 5-second timeout in disconnectDevice
            () => throw TimeoutException('Simulated disconnection timeout'),
          ));

      expect(
        () => bleService.disconnectDevice('VEEPEAK:1234'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to disconnect from device: TimeoutException: Disconnection timeout for device: VEEPEAK:1234',
          ),
        ),
      );
    });
    
    test('throws on disconnection failure', () async {
      when(mockAdapter.disconnectDevice(any)).thenThrow(Exception('Disconnect error'));

      expect(() => bleService.disconnectDevice('VEEPEAK:1234'), throwsException);
    });
  });

  group('getDeviceState', () {
    test('returns connection state', () async {
      when(mockAdapter.getConnectionStateStream(any)).thenAnswer((_) => connectionStreamController.stream);

      // Start the future and emit the state immediately
      final stateFuture = bleService.getDeviceState('VEEPEAK:1234');
      await Future.delayed(Duration(milliseconds: 10)); // Allow stream setup
      connectionStreamController.add(ConnectionStateUpdate(
        deviceId: 'VEEPEAK:1234',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ));

      final state = await stateFuture;
      expect(state, DeviceConnectionState.connected);
    });

    test('throws on timeout', () async {
      when(mockAdapter.getConnectionStateStream(any)).thenAnswer((_) => StreamController<ConnectionStateUpdate>.broadcast().stream);

      expect(
        () => bleService.getDeviceState('VEEPEAK:1234'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to get device state: TimeoutException: Connection state timeout',
          ),
        ),
      );
    });

    test('throws on failure', () async {
      when(mockAdapter.getConnectionStateStream(any)).thenThrow(Exception('Get state error'));

      expect(() => bleService.getDeviceState('VEEPEAK:1234'), throwsException);
    });
  });

  group('getDeviceStateStream', () {
    test('streams connection state', () async {
      when(mockAdapter.getConnectionStateStream(any)).thenAnswer((_) => connectionStreamController.stream);

      // Start listening to the stream
      final stream = bleService.getDeviceStateStream('VEEPEAK:1234');
      final expectation = expectLater(
        stream.take(1),
        emits(DeviceConnectionState.connected),
      );

      // Emit the state after a short delay to ensure stream is subscribed
      await Future.delayed(Duration(milliseconds: 10));
      connectionStreamController.add(ConnectionStateUpdate(
        deviceId: 'VEEPEAK:1234',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ));

      // Wait for the expectation to complete
      await expectation;
    });

    test('throws on stream failure', () async {
      when(mockAdapter.getConnectionStateStream(any)).thenThrow(Exception('Stream error'));

      expect(() => bleService.getDeviceStateStream('VEEPEAK:1234'), throwsException);
    });
  });

  group('requestMtu', () {
    test('requests MTU successfully', () async {
      when(mockAdapter.requestMtu(any, any)).thenAnswer((_) async {});

      await bleService.requestMtu('VEEPEAK:1234', 512);
      verify(mockAdapter.requestMtu('VEEPEAK:1234', 512)).called(1);
    });

    test('throws on MTU request failure', () async {
      when(mockAdapter.requestMtu(any, any)).thenThrow(Exception('MTU error'));

      expect(() => bleService.requestMtu('VEEPEAK:1234', 512), throwsException);
    });
  });

  group('clearGattCache', () {
    test('clears GATT cache successfully', () async {
      when(mockAdapter.clearGattCache(any)).thenAnswer((_) async {});

      await bleService.clearGattCache('VEEPEAK:1234');
      verify(mockAdapter.clearGattCache('VEEPEAK:1234')).called(1);
    });

    test('throws on GATT cache clear failure', () async {
      when(mockAdapter.clearGattCache(any)).thenThrow(Exception('GATT cache error'));

      expect(() => bleService.clearGattCache('VEEPEAK:1234'), throwsException);
    });
  });

  group('readCharacteristic', () {
    test('reads characteristic successfully', () async {
      when(mockAdapter.readCharacteristic(any)).thenAnswer((_) async => [0x41, 0x0C, 0x1A, 0xF8]);

      final value = await bleService.readCharacteristic(mockCharacteristic);
      expect(value, [0x41, 0x0C, 0x1A, 0xF8]);
      verify(mockAdapter.readCharacteristic(mockCharacteristic)).called(1);
    });

    test('throws on read failure', () async {
      when(mockAdapter.readCharacteristic(any)).thenThrow(Exception('Read error'));

      expect(() => bleService.readCharacteristic(mockCharacteristic), throwsException);
    });
  });

  group('writeCharacteristic', () {
    test('writes characteristic successfully', () async {
      when(mockAdapter.writeCharacteristic(any, any, withResponse: anyNamed('withResponse'))).thenAnswer((_) async {});

      await bleService.writeCharacteristic(mockCharacteristic, [0x41, 0x54, 0x5A], withResponse: true);
      verify(mockAdapter.writeCharacteristic(mockCharacteristic, [0x41, 0x54, 0x5A], withResponse: true)).called(1);
    });

    test('throws on write failure', () async {
      when(mockAdapter.writeCharacteristic(any, any, withResponse: anyNamed('withResponse')))
          .thenThrow(Exception('Write error'));

      expect(() => bleService.writeCharacteristic(mockCharacteristic, [0x41, 0x54, 0x5A]), throwsException);
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