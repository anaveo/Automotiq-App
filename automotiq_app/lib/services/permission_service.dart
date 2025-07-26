import 'package:permission_handler/permission_handler.dart';

/// [PermissionService] is an abstract interface that defines
/// methods and properties for accessing and requesting Bluetooth
/// and location permissions in a mockable and testable way.
///
/// This wrapper exists so that we can easily inject a fake/mock version
/// of the permission system during unit testing. The `permission_handler`
/// plugin uses static methods and properties that are hard to mock directly.
/// By abstracting these calls, we enable flexible and test-friendly code.
abstract class PermissionService {
  /// Gets the current status of the Bluetooth Scan permission.
  Future<PermissionStatus> get bluetoothScanStatus;

  /// Gets the current status of the Bluetooth Connect permission.
  Future<PermissionStatus> get bluetoothConnectStatus;

  /// Gets the current status of the Location permission.
  Future<PermissionStatus> get locationStatus;

  /// Requests the Bluetooth Scan permission from the user.
  Future<PermissionStatus> requestBluetoothScan();

  /// Requests the Bluetooth Connect permission from the user.
  Future<PermissionStatus> requestBluetoothConnect();

  /// Requests the Location permission from the user.
  Future<PermissionStatus> requestLocation();
}

/// [SystemPermissionService] is the default implementation of [PermissionService]
/// that directly delegates to the `permission_handler` plugin.
///
/// This class is injected into production code, while tests can inject
/// a mock implementation that returns desired permission states.
///
/// Use this class in your app like:
/// ```dart
/// final bleService = BleService(permissionService: SystemPermissionService());
/// ```
class SystemPermissionService implements PermissionService {
  @override
  Future<PermissionStatus> get bluetoothScanStatus => Permission.bluetoothScan.status;

  @override
  Future<PermissionStatus> get bluetoothConnectStatus => Permission.bluetoothConnect.status;

  @override
  Future<PermissionStatus> get locationStatus => Permission.location.status;

  @override
  Future<PermissionStatus> requestBluetoothScan() => Permission.bluetoothScan.request();

  @override
  Future<PermissionStatus> requestBluetoothConnect() => Permission.bluetoothConnect.request();

  @override
  Future<PermissionStatus> requestLocation() => Permission.location.request();
}
