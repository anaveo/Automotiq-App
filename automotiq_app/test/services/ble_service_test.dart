import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:automotiq_app/services/ble_service.dart';
import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBluetoothAdapter mockAdapter;
  late MockPermissionService mockPermissions;
  late BleService bleService;
  late StreamController<DiscoveredDevice> scanStreamController;
  late StreamController<ConnectionStateUpdate> connectionStreamController;
  late MockDiscoveredDevice mockDevice;
  late QualifiedCharacteristic mockCharacteristic;

  setUp(() {
    // Initialize mocks
    mockAdapter = MockBluetoothAdapter();
    mockPermissions = MockPermissionService();
    mockDevice = MockDiscoveredDevice();
    bleService = BleService(adapter: mockAdapter, permissionService: mockPermissions);

    // Stub permission responses
    when(mockPermissions.bluetoothScanStatus).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.bluetoothConnectStatus).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.locationStatus).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.requestBluetoothScan()).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.requestBluetoothConnect()).thenAnswer((_) async => PermissionStatus.granted);
    when(mockPermissions.requestLocation()).thenAnswer((_) async => PermissionStatus.granted);

    // Setup streams
    scanStreamController = StreamController<DiscoveredDevice>.broadcast();
    connectionStreamController = StreamController<ConnectionStateUpdate>.broadcast();
    when(mockAdapter.scanForDevices(withServices: anyNamed('withServices')))
        .thenAnswer((_) => scanStreamController.stream);
    when(mockAdapter.connectToDevice(
      id: anyNamed('id'),
      servicesWithCharacteristicsToDiscover: anyNamed('servicesWithCharacteristicsToDiscover'),
      connectionTimeout: anyNamed('connectionTimeout'),
    )).thenAnswer((_) => connectionStreamController.stream);

    // Stub device
    when(mockDevice.id).thenReturn('VEEPEAK:1234');
    when(mockDevice.name).thenReturn('VEEPEAK');

    // Setup mock characteristic
    mockCharacteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse('0000FFE0-0000-1000-8000-00805F9B34FB'),
      characteristicId: Uuid.parse('0000FFE1-0000-1000-8000-00805F9B34FB'),
      deviceId: 'VEEPEAK:1234',
    );
  });

  tearDown(() async {
    await scanStreamController.close();
    await connectionStreamController.close();
    await bleService.dispose(); // Ensure cleanup
  });

  group('scanForDevices', () {
    test('returns unique devices', () async {
      final mockDevice = MockDiscoveredDevice();
      when(mockDevice.id).thenReturn('VEEPEAK:1234');
      when(mockDevice.name).thenReturn('VEEPEAK');

      // Simulate scan results with duplicate device
      when(mockAdapter.scanForDevices(withServices: anyNamed('withServices')))
          .thenAnswer((_) => Stream.fromIterable([mockDevice, mockDevice]));

      final scanFuture = bleService.scanForDevices(timeout: Duration(milliseconds: 100));
      await Future.delayed(Duration(milliseconds: 110)); // Wait for scan completion

      final devices = await scanFuture;

      expect(devices.length, 1); // Should filter duplicates
      expect(devices[0].id, 'VEEPEAK:1234');
      expect(devices[0].name, 'VEEPEAK');
      verify(mockAdapter.scanForDevices(withServices: anyNamed('withServices'))).called(1);
    });

    test('throws on permission denied', () async {
      when(mockPermissions.bluetoothScanStatus).thenAnswer((_) async => PermissionStatus.denied);
      when(mockPermissions.requestBluetoothScan()).thenAnswer((_) async => PermissionStatus.denied);

      expect(
        () => bleService.scanForDevices(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Bluetooth scan permission denied',
          ),
        ),
      );
    });

    test('throws on scan failure', () async {
      when(mockAdapter.scanForDevices(withServices: anyNamed('withServices')))
          .thenAnswer((_) => throw Exception('Scan error'));

      await expectLater(
        bleService.scanForDevices(timeout: Duration(milliseconds: 100)),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to scan for devices: Exception: Scan error',
          ),
        ),
      );
    });
  });

  group('connectToDevice', () {
    test('connects to device and updates state', () async {
      when(mockAdapter.connectToDevice(
        id: 'VEEPEAK:1234',
        servicesWithCharacteristicsToDiscover: anyNamed('servicesWithCharacteristicsToDiscover'),
        connectionTimeout: anyNamed('connectionTimeout'),
      )).thenAnswer((_) => connectionStreamController.stream);

      // Start connection and emit state
      final connectionFuture = bleService.connectToDevice(mockDevice.id);
      await Future.delayed(Duration(milliseconds: 10)); // Allow stream setup
      connectionStreamController.add(ConnectionStateUpdate(
        deviceId: 'VEEPEAK:1234',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ));

      await connectionFuture;

      expect(bleService.getDeviceState(), DeviceConnectionState.connected);
      verify(mockAdapter.connectToDevice(
        id: 'VEEPEAK:1234',
        servicesWithCharacteristicsToDiscover: anyNamed('servicesWithCharacteristicsToDiscover'),
        connectionTimeout: anyNamed('connectionTimeout'),
      )).called(1);
    });

    test('throws on connection timeout', () async {
      when(mockAdapter.connectToDevice(
        id: 'VEEPEAK:1234',
        servicesWithCharacteristicsToDiscover: anyNamed('servicesWithCharacteristicsToDiscover'),
        connectionTimeout: anyNamed('connectionTimeout'),
      )).thenAnswer((_) => throw TimeoutException('Connection timeout'));

      await expectLater(
        bleService.connectToDevice(mockDevice.id, connectionTimeout: Duration(seconds: 5)),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to connect to device: TimeoutException: Connection timeout',
          ),
        ),
      );
    });

    test('throws on connection failure', () async {
      when(mockAdapter.connectToDevice(
        id: 'VEEPEAK:1234',
        servicesWithCharacteristicsToDiscover: anyNamed('servicesWithCharacteristicsToDiscover'),
        connectionTimeout: anyNamed('connectionTimeout'),
      )).thenAnswer((_) => throw Exception('Connection error'));

      await expectLater(
        bleService.connectToDevice(mockDevice.id),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to connect to device: Exception: Connection error',
          ),
        ),
      );
    });
  });

  group('disconnectDevice', () {
    test('disconnects device and updates state', () async {
      // Stub the adapter's connectToDevice to return the stream controller
      when(mockAdapter.connectToDevice(
        id: anyNamed('id'),
        servicesWithCharacteristicsToDiscover: anyNamed('servicesWithCharacteristicsToDiscover'),
        connectionTimeout: anyNamed('connectionTimeout'),
      )).thenAnswer((_) => connectionStreamController.stream);

      // Capture emitted states
      final emittedStates = <DeviceConnectionState>[];
      final subscription = bleService.connectionStateStream.listen(emittedStates.add);

      // Connect
      await bleService.connectToDevice(mockDevice.id);
      connectionStreamController.add(ConnectionStateUpdate(
        deviceId: 'VEEPEAK:1234',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ));
      await Future.delayed(Duration(milliseconds: 10)); // allow state update

      // Disconnect
      await bleService.disconnectDevice();
      await Future.delayed(Duration(milliseconds: 10)); // allow state update

      await subscription.cancel();

      expect(emittedStates, [
        DeviceConnectionState.connecting,
        DeviceConnectionState.connected,
        DeviceConnectionState.disconnecting,
        DeviceConnectionState.disconnected,
      ]);

      expect(bleService.getDeviceState(), DeviceConnectionState.disconnected);
    });
  });

  group('getDeviceState', () {
    test('returns current connection state', () async {
      // Set up a connection to update state
      when(mockAdapter.connectToDevice(
        id: anyNamed('id'),
        servicesWithCharacteristicsToDiscover: anyNamed('servicesWithCharacteristicsToDiscover'),
        connectionTimeout: anyNamed('connectionTimeout'),
      )).thenAnswer((_) => connectionStreamController.stream);

      // Simulate a connection
      await bleService.connectToDevice(mockDevice.id);
      connectionStreamController.add(ConnectionStateUpdate(
        deviceId: 'VEEPEAK:1234',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ));
      await Future.delayed(Duration(milliseconds: 10)); // Allow state update

      final state = bleService.getDeviceState();
      expect(state, DeviceConnectionState.connected);
    });

    test('returns disconnected state when no connection exists', () {
      final state = bleService.getDeviceState();
      expect(state, DeviceConnectionState.disconnected);
    });
  });

 group('requestMtu', () {
    test('requests MTU successfully', () async {
      when(mockAdapter.requestMtu(deviceId: anyNamed('deviceId'), mtu: anyNamed('mtu')))
          .thenAnswer((_) async => 512);

      final result = await bleService.requestMtu(deviceId: 'VEEPEAK:1234', mtu: 512);
      expect(result, 512);
      verify(mockAdapter.requestMtu(deviceId: 'VEEPEAK:1234', mtu: 512)).called(1);
    });

    test('throws on MTU request failure', () async {
      when(mockAdapter.requestMtu(deviceId: anyNamed('deviceId'), mtu: anyNamed('mtu')))
          .thenThrow(Exception('MTU error'));

      await expectLater(
        bleService.requestMtu(deviceId: 'VEEPEAK:1234', mtu: 512),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to request MTU: Exception: MTU error',
          ),
        ),
      );
    });
  });

  group('readCharacteristic', () {
    test('reads characteristic successfully', () async {
      when(mockAdapter.readCharacteristic(any))
          .thenAnswer((_) async => [0x41, 0x0C, 0x1A, 0xF8]);

      final value = await bleService.readCharacteristic(mockCharacteristic);
      expect(value, [0x41, 0x0C, 0x1A, 0xF8]);
      verify(mockAdapter.readCharacteristic(mockCharacteristic)).called(1);
    });

    test('throws on read failure', () async {
      when(mockAdapter.readCharacteristic(any))
          .thenThrow(Exception('Read error'));

      await expectLater(
        bleService.readCharacteristic(mockCharacteristic),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to read characteristic: Exception: Read error',
          ),
        ),
      );
    });
  });

  group('writeCharacteristic', () {
    test('writes characteristic with response successfully', () async {
      when(mockAdapter.writeCharacteristicWithResponse(any, value: anyNamed('value')))
          .thenAnswer((_) async => {});

      await bleService.writeCharacteristic(mockCharacteristic, [0x41, 0x54, 0x5A], withResponse: true);
      verify(mockAdapter.writeCharacteristicWithResponse(mockCharacteristic, value: [0x41, 0x54, 0x5A])).called(1);
      verifyNever(mockAdapter.writeCharacteristicWithoutResponse(any, value: anyNamed('value')));
    });

    test('writes characteristic without response successfully', () async {
      when(mockAdapter.writeCharacteristicWithoutResponse(any, value: anyNamed('value')))
          .thenAnswer((_) async => {});

      await bleService.writeCharacteristic(mockCharacteristic, [0x41, 0x54, 0x5A], withResponse: false);
      verify(mockAdapter.writeCharacteristicWithoutResponse(mockCharacteristic, value: [0x41, 0x54, 0x5A])).called(1);
      verifyNever(mockAdapter.writeCharacteristicWithResponse(any, value: anyNamed('value')));
    });

    test('throws on write with response failure', () async {
      when(mockAdapter.writeCharacteristicWithResponse(any, value: anyNamed('value')))
          .thenThrow(Exception('Write error'));

      await expectLater(
        bleService.writeCharacteristic(mockCharacteristic, [0x41, 0x54, 0x5A], withResponse: true),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to write characteristic: Exception: Write error',
          ),
        ),
      );
    });

    test('throws on write without response failure', () async {
      when(mockAdapter.writeCharacteristicWithoutResponse(any, value: anyNamed('value')))
          .thenThrow(Exception('Write error'));

      await expectLater(
        bleService.writeCharacteristic(mockCharacteristic, [0x41, 0x54, 0x5A], withResponse: false),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to write characteristic: Exception: Write error',
          ),
        ),
      );
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