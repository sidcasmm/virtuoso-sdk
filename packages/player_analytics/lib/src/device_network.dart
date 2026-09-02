import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

Future<DeviceDetails> collectDeviceDetails() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (!kIsWeb && Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return DeviceDetails(
        os: 'android',
        osVersion: info.version.release,
        manufacturer: info.manufacturer,
        model: info.model,
        name: info.model,
        type: 'phone',
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      final info = await plugin.iosInfo;
      final model = info.model.toLowerCase();
      return DeviceDetails(
        os: 'ios',
        osVersion: info.systemVersion,
        manufacturer: 'Apple',
        model: info.utsname.machine,
        name: info.name,
        type: model.contains('ipad') ? 'tablet' : 'phone',
      );
    }
  } catch (_) {}
  return DeviceDetails(
    os: defaultTargetPlatform.name,
    osVersion: kIsWeb ? null : Platform.operatingSystemVersion,
    type: 'unknown',
  );
}

Future<NetworkDetails> collectNetworkDetails() async {
  try {
    final results = await Connectivity().checkConnectivity();
    final first = results.isEmpty ? ConnectivityResult.other : results.first;
    final type = switch (first) {
      ConnectivityResult.wifi => 'wifi',
      ConnectivityResult.mobile => 'cellular',
      ConnectivityResult.ethernet => 'ethernet',
      ConnectivityResult.vpn => 'other',
      ConnectivityResult.bluetooth => 'other',
      ConnectivityResult.other => 'other',
      ConnectivityResult.none => 'unknown',
      ConnectivityResult.satellite => 'other',
    };
    return NetworkDetails(connectionType: type);
  } catch (_) {
    return const NetworkDetails(connectionType: 'unknown');
  }
}
