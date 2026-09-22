import 'package:flutter/foundation.dart';

enum FlaskTarget { local, deployed }

// Change this to FlaskTarget.deployed to use your server, then restart/rebuild
// Flutter. OpenAI's key and model are configured separately in backend/.env.
const activeFlaskTarget = FlaskTarget.local;

// Use Flask's origin only, without an /api path or the Flutter preview port.
// For a physical phone, set localFlaskUrl to your computer's LAN IP and port.
const localFlaskUrl = 'http://127.0.0.1:5000';
const deployedFlaskUrl = 'http://31.97.178.214:5001';

/// Every invoice and shopping request uses this configuration. Old saved server
/// preferences are intentionally ignored so changing this file always takes effect.
String flaskApiUrl({
  FlaskTarget target = activeFlaskTarget,
  String localUrl = localFlaskUrl,
  String deployedUrl = deployedFlaskUrl,
  TargetPlatform? platform,
  bool? isWeb,
}) {
  final url = (target == FlaskTarget.local ? localUrl : deployedUrl).trim();
  if (target != FlaskTarget.local ||
      (isWeb ?? kIsWeb) ||
      (platform ?? defaultTargetPlatform) != TargetPlatform.android) {
    return url;
  }

  // The Android emulator reaches the host computer through 10.0.2.2.
  // A configured LAN address is left intact for physical-device testing.
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !{
        'localhost',
        '127.0.0.1',
        '::1',
        '[::1]',
      }.contains(uri.host.toLowerCase())) {
    return url;
  }
  return uri.replace(host: '10.0.2.2').toString();
}
