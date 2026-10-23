# Full version purchase

5-Minute Kanji sells two store products. There is no third-party checkout.

- Lifetime product id: `full_curriculum_unlock` (non-consumable)
- Monthly product id: `full_curriculum_monthly` (auto-renewing subscription)
- Prices to configure: **$59.99 USD** once, and **$6.99 USD** per month
- The app displays the prices returned by the store, not hardcoded dollar amounts
- The first 50 kanji learned through the normal Learn flow are the only trial. The subscription has no free trial and no introductory offer.

Full access is the lifetime purchase, or a monthly subscription that is active, in a grace period, or in billing retry. Lifetime wins. When a subscription expires or is refunded, new kanji past the 50 lock again. Reviews of kanji already learned stay available, and schedules are not deleted. Buying again or buying lifetime restores new kanji immediately.

The product is not created by this repository. App Store Connect and Play Console still need the steps below. Until those products exist, the purchase button cannot load a price or complete a sale. The free trial still works.

## App Store Connect

1. In the app's Agreements, Tax, and Banking section, accept the Paid Applications agreement.
2. Create an In-App Purchase of type **Non-Consumable**.
3. Set the product id to exactly `full_curriculum_unlock`.
4. Set the price to the **$59.99** tier. Apple localizes the displayed price.
5. Add a display name and description, such as "Full curriculum" / "Learn every kanji, with no subscription."
6. Add a review screenshot and submit the product with a binary that includes this build.
7. In Xcode, enable the **In-App Purchase** capability for the Runner target and use the same bundle id as the app record.
8. Sandbox testing uses a Sandbox Apple ID. Restore Purchases asks StoreKit for both products.
9. Create a subscription group, for example `full_curriculum`, with one auto-renewable subscription.
10. Set that product id to exactly `full_curriculum_monthly`, duration 1 month, price the **$6.99** tier. Do not add a free trial or introductory offer.
11. Add the subscription disclosure links. The app currently opens in-app placeholder screens for Terms of Use and Privacy Policy. Replace those with public URLs before review. App Store Connect also needs the privacy policy URL.

The app does not call restore on every launch. On iOS 15 and later it reads StoreKit 2 transactions quietly on launch and when the app returns to the foreground. Restore Purchases is what asks StoreKit to replay current entitlements, including the subscription. After a reinstall, the user taps **Restore Purchases**.

## Google Play Console

1. Upload a build that includes the `com.android.vending.BILLING` permission (already in the app manifest; the billing plugin also merges it).
2. Create a **one-time product** (not a subscription and not a consumable).
3. Set the product id to exactly `full_curriculum_unlock`.
4. Set the price to **$59.99 USD** and let Play fill in the other regions.
5. Activate the product.
6. Create a subscription with product id `full_curriculum_monthly` and one base plan id `monthly`, billed every month at **$6.99 USD**. Do not add an offer or free trial.
7. Activate both products.
8. License testers can buy without being charged. Add them under License testing and use a Play test card. The app re-queries owned one-time products and subscriptions on startup, on resume, and when the user taps Restore Purchases.

Play acknowledges a purchase only after the app accepts a verified purchase update. An unacknowledged purchase is refunded after three days. Pending purchases (for example a payment that has not cleared) do not unlock the curriculum.

Manage subscription opens `https://play.google.com/store/account/subscriptions?sku=full_curriculum_monthly&package=com.example.fiveminutekanji`. The package name is `com.example.fiveminutekanji` from `android/app/build.gradle.kts`. Change `androidApplicationId` in `curriculum_products.dart` if that id changes.

## What the app treats as proof

The lifetime unlock is granted only when the store reports `purchased` or `restored` for `full_curriculum_unlock` and the purchase includes non-empty verification data. The monthly unlock is granted for the same statuses on `full_curriculum_monthly` when the subscription is active, in grace, or in billing retry. Tapping a button, canceling, a store error, or a pending payment does not grant either one.

A local cache stores the lifetime flag, the subscription state, and the subscription expiry so the app can open offline. On Android, a successful query of current purchases replaces that cache, including a refund or a lapsed subscription. On iOS 15+, a quiet read of StoreKit transactions does the same for the subscription. If the store cannot be reached, the cache is left as it is, and an expiry date that has passed locks new kanji until the store says otherwise.

Play's client query does not return subscriptions in account hold. Those are treated as lapsed until the store lists them again. Grace period is recognized when Play still returns the subscription after the paid month. StoreKit reports billing retry when a restored current entitlement is past its expiration date. There is no server in this repository to read Apple's renewal status or Play's `purchases.subscriptionsv2`.

That cache is not tamper-proof. A rooted device can edit local storage. A backend should verify the receipt before you treat the unlock as authoritative:

- Send `verificationData` (the App Store signed transaction, or the Play purchase token) to your server.
- Apple: verify the JWS with the App Store Server API. Require this product id, your bundle id, an ownership type of purchased, and no revocation date.
- Google lifetime: call the Play Developer API `purchases.products.get` with the package name, `full_curriculum_unlock`, and the purchase token. Require `purchaseState` purchased, then acknowledge if Play has not already.
- Google monthly: call `purchases.subscriptionsv2.get` and accept `SUBSCRIPTION_STATE_ACTIVE`, `SUBSCRIPTION_STATE_IN_GRACE_PERIOD`, and `SUBSCRIPTION_STATE_IN_ACCOUNT_HOLD` if billing retry should keep access.

This repository does not include that server. Client-side store checks are what the app can do on its own.

## Trial count

A kanji is counted when the Learn flow introduces it for the first time. Mark as Known, placement "already known", and placement confirmation cards do not count. The same kanji is not counted twice. The count is stored beside the rest of progress and is not cleared by a placement retake, a finished session, or a settings change.

The first launch after this feature reads existing schedules once. Cards that were already introduced through study are counted, so earlier progress is not turned into a fresh 50-kanji trial. Schedules and intervals are not rewritten. Untouched Mark as Known cards, unreviewed placement confirmations, and the first few long-interval known-card reviews stay out of that historical count.
