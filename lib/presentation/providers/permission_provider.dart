import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/datasources/platform_channel_datasource.dart';
import 'mesh_provider.dart';

class PermissionState {
  final bool isChecking;
  final bool allGranted;
  final bool isBatteryOptimizationIgnored;
  final bool isBluetoothEnabled;
  final bool isLocationServiceEnabled;
  final Map<Permission, PermissionStatus> statuses;

  const PermissionState({
    required this.isChecking,
    required this.allGranted,
    this.isBatteryOptimizationIgnored = false,
    this.isBluetoothEnabled = true,
    this.isLocationServiceEnabled = true,
    required this.statuses,
  });

  PermissionState copyWith({
    bool? isChecking,
    bool? allGranted,
    bool? isBatteryOptimizationIgnored,
    bool? isBluetoothEnabled,
    bool? isLocationServiceEnabled,
    Map<Permission, PermissionStatus>? statuses,
  }) {
    return PermissionState(
      isChecking: isChecking ?? this.isChecking,
      allGranted: allGranted ?? this.allGranted,
      isBatteryOptimizationIgnored:
          isBatteryOptimizationIgnored ?? this.isBatteryOptimizationIgnored,
      isBluetoothEnabled: isBluetoothEnabled ?? this.isBluetoothEnabled,
      isLocationServiceEnabled:
          isLocationServiceEnabled ?? this.isLocationServiceEnabled,
      statuses: statuses ?? this.statuses,
    );
  }
}

class PermissionNotifier extends StateNotifier<PermissionState> {
  final PlatformChannelDataSource _platformDataSource;

  PermissionNotifier(this._platformDataSource)
      : super(const PermissionState(
          isChecking: true,
          allGranted: false,
          isBatteryOptimizationIgnored: false,
          isBluetoothEnabled: true,
          isLocationServiceEnabled: true,
          statuses: {},
        )) {
    checkAndRequestPermissions();
  }

  Future<void> checkAndRequestPermissions() async {
    state = state.copyWith(isChecking: true);

    List<Permission> permissions = [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
      Permission.notification,
    ];

    Map<Permission, PermissionStatus> statuses = {};
    for (var perm in permissions) {
      final status = await perm.request();
      statuses[perm] = status;
    }

    bool allGranted = statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );

    final batteryOptStatus = await Permission.ignoreBatteryOptimizations.status;
    final btEnabled = await _platformDataSource.isBluetoothEnabled();
    final locEnabled = await _platformDataSource.isLocationServiceEnabled();

    state = PermissionState(
      isChecking: false,
      allGranted: allGranted,
      isBatteryOptimizationIgnored: batteryOptStatus.isGranted,
      isBluetoothEnabled: btEnabled,
      isLocationServiceEnabled: locEnabled,
      statuses: statuses,
    );
  }

  Future<bool> checkBluetoothState() async {
    final btEnabled = await _platformDataSource.isBluetoothEnabled();
    state = state.copyWith(isBluetoothEnabled: btEnabled);
    return btEnabled;
  }

  Future<bool> requestEnableBluetooth() async {
    final success = await _platformDataSource.requestEnableBluetooth();
    for (int i = 0; i < 7; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final enabled = await checkBluetoothState();
      if (enabled) return true;
    }
    return success;
  }

  Future<bool> checkLocationServiceState() async {
    final locEnabled = await _platformDataSource.isLocationServiceEnabled();
    state = state.copyWith(isLocationServiceEnabled: locEnabled);
    return locEnabled;
  }

  Future<bool> requestEnableLocationService() async {
    final success = await _platformDataSource.requestEnableLocationService();
    await Future.delayed(const Duration(milliseconds: 1000));
    await checkLocationServiceState();
    return success;
  }

  Future<void> requestBatteryOptimizationExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    state = state.copyWith(isBatteryOptimizationIgnored: status.isGranted);
  }
}

final permissionProvider =
    StateNotifierProvider<PermissionNotifier, PermissionState>((ref) {
  final platformDs = ref.watch(platformDataSourceProvider);
  return PermissionNotifier(platformDs);
});
