/// Entry point.
///
/// Startup order matters: preferences and the keychain are read *before* the
/// first frame so [GoRouter]'s redirect can make a correct decision on frame
/// one and a signed-in user never sees the login screen flash.
library;

import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app/app.dart';
import 'core/network/api_client.dart';
import 'core/network/token_store.dart';
import 'core/providers.dart';
import 'core/storage/prefs.dart';
import 'core/storage/secure_store.dart';
import 'core/utils/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only. Every screen here is a form or a list; a landscape layout
  // would be a second design to maintain for no user benefit.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    Log.error('Flutter framework error', details.exception, details.stack);
  };

  final Bootstrap bootstrap = await _bootstrap();

  runApp(
    ProviderScope(
      overrides: <Override>[
        bootstrapProvider.overrideWithValue(bootstrap),
      ],
      child: const BankSheetApp(),
    ),
  );
}

Future<Bootstrap> _bootstrap() async {
  final Prefs prefs = await Prefs.open();
  final SecureStore secure = SecureStore();
  final TokenStore tokens = TokenStore(secure);

  // Reading the refresh token here is what lets the router avoid a splash
  // flicker; see the redirect in `app/router.dart`.
  await tokens.restore();

  final ClientIdentity identity = await _identity(secure);

  Log.info('BankSheet Pro ${identity.appVersion} on ${identity.platform}');

  return Bootstrap(
    prefs: prefs,
    secureStore: secure,
    tokenStore: tokens,
    identity: identity,
  );
}

Future<ClientIdentity> _identity(SecureStore secure) async {
  String version = '1.0.0';
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) {
      version = info.version;
    }
  } on Exception catch (e) {
    Log.warn('Could not read package info: $e');
  }

  String platform = 'unknown';
  String name = 'Mobile device';

  try {
    final DeviceInfoPlugin device = DeviceInfoPlugin();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final IosDeviceInfo ios = await device.iosInfo;
      platform = 'ios';
      name = ios.name.isNotEmpty ? ios.name : ios.utsname.machine;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final AndroidDeviceInfo android = await device.androidInfo;
      platform = 'android';
      name = '${android.manufacturer} ${android.model}'.trim();
    }
  } on Exception catch (e) {
    // A device that refuses to identify itself is not a reason to fail startup;
    // the server only uses these values for the user's device list.
    Log.warn('Could not read device info: $e');
  }

  // A per-install identifier, minted once and kept in the keychain. Deliberately
  // NOT a hardware id — uninstalling resets it, which keeps the app clear of the
  // stores' device-tracking disclosure requirements while still letting the
  // server revoke one device.
  String? deviceId = await secure.readDeviceId();
  if (deviceId == null || deviceId.isEmpty) {
    deviceId = _mintDeviceId();
    await secure.writeDeviceId(deviceId);
  }

  return ClientIdentity(
    appVersion: version,
    platform: platform,
    deviceName: name.isEmpty ? 'Mobile device' : name,
    deviceId: deviceId,
  );
}

/// 128 bits of hex from the platform's CSPRNG.
String _mintDeviceId() {
  final Random random = Random.secure();
  return List<int>.generate(16, (_) => random.nextInt(256))
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
