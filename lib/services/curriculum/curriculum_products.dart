/// Non-consumable product id shared by the app, App Store Connect, and Play Console.
const String fullCurriculumUnlock = 'full_curriculum_unlock';

/// Auto-renewing monthly subscription. Same naming style as [fullCurriculumUnlock].
///
/// iOS: one subscription group containing only this product.
/// Android: one subscription with a single monthly base plan id [monthlyBasePlanId].
const String fullCurriculumMonthly = 'full_curriculum_monthly';

/// Play Console base plan id for [fullCurriculumMonthly]. No offer, no free trial.
const String monthlyBasePlanId = 'monthly';

/// Must match `applicationId` in android/app/build.gradle.kts.
const String androidApplicationId = 'com.blinklabsapps.fiveminutekanji';

/// Unique kanji that can be learned before the full curriculum is purchased.
const int freeKanjiLimit = 50;

const String appleSubscriptionManagementUrl =
    'https://apps.apple.com/account/subscriptions';

String androidSubscriptionManagementUrl() {
  return 'https://play.google.com/store/account/subscriptions'
      '?sku=$fullCurriculumMonthly&package=$androidApplicationId';
}
