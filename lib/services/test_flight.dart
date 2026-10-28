import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _distributionChannel = MethodChannel('fiveminutekanji/distribution');

/// True when Settings should offer the Reinforcement Day debugger.
///
/// Debug runs always qualify. A release build qualifies when this install
/// came from TestFlight. An App Store install does not.
bool reinforcementDebuggerVisible({
  required bool debugMode,
  required bool testFlight,
}) {
  return debugMode || testFlight;
}

/// TestFlight's App Store receipt is named `sandboxReceipt`.
/// The public App Store receipt is named `receipt`.
bool isTestFlightReceipt(String? receiptName) {
  return receiptName == 'sandboxReceipt';
}

/// Asks iOS for the receipt file name. Other platforms, and a missing
/// native handler, are treated as an ordinary install.
Future<bool> installedFromTestFlight() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return false;
  try {
    final name = await _distributionChannel.invokeMethod<String>('receiptName');
    return isTestFlightReceipt(name);
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
