import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'analytics_service.dart';

/// The app-wide [AnalyticsService], or a no-op when a test did not provide one.
AnalyticsService readAnalytics(BuildContext context) {
  try {
    return context.read<AnalyticsService>();
  } on ProviderNotFoundException {
    return AnalyticsService();
  }
}
