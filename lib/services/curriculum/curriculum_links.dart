import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'curriculum_products.dart';

/// Store page where the user can cancel a subscription. The app cannot cancel it.
String subscriptionManagementUrl() {
  if (!kIsWeb && Platform.isAndroid) return androidSubscriptionManagementUrl();
  return appleSubscriptionManagementUrl;
}

Future<bool> openSubscriptionManagement() {
  return launchUrl(
    Uri.parse(subscriptionManagementUrl()),
    mode: LaunchMode.externalApplication,
  );
}
