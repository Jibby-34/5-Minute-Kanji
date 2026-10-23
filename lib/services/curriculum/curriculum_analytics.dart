/// Purchase events. No analytics SDK is installed.
///
/// TODO: Forward these to the app's analytics layer when one exists.
/// Events: paywall_viewed, purchase_started(product), purchase_succeeded(product),
/// purchase_cancelled(product), restore_tapped.
class CurriculumAnalytics {
  const CurriculumAnalytics();

  void paywallViewed() {}

  void purchaseStarted(String productId) {}

  void purchaseSucceeded(String productId) {}

  void purchaseCancelled(String productId) {}

  void restoreTapped() {}
}
