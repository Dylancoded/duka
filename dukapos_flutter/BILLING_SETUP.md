# DukaPOS Google Play subscriptions

This project uses Flutter's maintained `in_app_purchase` plugin (`3.3.1`) for the Android purchase UI. Google Play Billing Library 9.1.0 is the current native stable release at the time of implementation; new apps and updates must use Billing Library 8 or newer. The Flutter plugin supports Android SDK 24+, loads Play-localized product details, emits purchase updates through `purchaseStream`, and requires a purchase to be completed only after verification and delivery.

The client never grants paid access from a local purchase result. It sends the Play purchase token to `billingVerify`, and only caches the entitlement returned by the server. If the server cannot verify the purchase, the user remains on the cached/free experience.

## Product IDs

Create six subscriptions in Play Console with these exact subscription product IDs:

- `starter_monthly`
- `starter_annual`
- `business_monthly`
- `business_annual`
- `multibranch_monthly`
- `multibranch_annual`

The app expects each product to be configured as an auto-renewing base plan. Configure the monthly products with a one-month billing period and the annual products with a one-year period. The intended price for `starter_monthly` is now **KSh 300/month**, replacing the previous KSh 499 target. Change the Kenya price for the `starter_monthly` base plan in Play Console; the app cannot change a Play price from Dart. Google Play remains the source of truth and returns the localized price shown in the paywall. Add any free trial or introductory offer to the relevant base plan.

## Firestore remote configuration

Create a `billingPlans` collection. Each active document can use the following shape. The document ID can be the product ID or a stable plan key.

```json
{
  "active": true,
  "plan": "business",
  "productId": "business_monthly",
  "interval": "monthly",
  "displayName": "Business",
  "description": "Controls for a busy store",
  "maxUsers": 5,
  "maxBranches": 1,
  "maxProducts": 5000,
  "features": {
    "reports": true,
    "customers": true,
    "audit": true,
    "mpesa": true,
    "offlineSales": true
  }
}
```

The server returns active documents through `billingCatalog`. If the collection is empty, the Functions fallback catalog is used so the app remains usable during initial setup. Set `targetPriceKsh: 300` on the `starter_monthly` Firestore document as the requested reference price. This field is informational; update the actual charge in Play Console. Treat Firestore as the source of truth for limits and feature flags, and Play Console as the source of truth for prices.

A business document receives a `billing` object containing the verified plan, product ID, subscription status, expiry, source and a one-way purchase-token hash. Raw purchase tokens are retained only in the restricted `billingTokens` collection so RTDN can find the owning business. Apply Firestore rules that prevent clients from writing either collection directly.

## Google Play Console setup

1. Create or select the application whose package name is `duka.pos`. Upload the app to an internal or closed test track before testing subscriptions.
2. In **Monetize > Products > Subscriptions**, create the six product IDs listed above. Do not rename them after publishing.
3. Add a base plan to each subscription. Use monthly and annual recurring periods matching the product ID. For `starter_monthly`, set the Kenya price to **KSh 300** instead of KSh 499. Set prices for other countries as needed. Add optional free-trial or introductory offers.
4. Add license testers under **Settings > License testing**. Testers should use a Google account on a Play-licensed device and install the app from the test track, not by sideloading an unsigned APK.
5. Configure the subscription grace period and account-hold period for each base plan. The server maps Play states to `active`, `grace_period`, `account_hold`, `pending`, `canceled`, or `expired`.
6. Under **Monetize > Monetization setup** or the Play Developer API access area, link the Play Developer account to the Google Cloud project used by Firebase Functions.
7. Configure Real-time developer notifications with a Google Cloud Pub/Sub topic. Use a topic such as `projects/PROJECT_ID/topics/play-rtdn-dukapos` and set the topic in Play Console for this application.
8. Grant the Google-managed Play notification publisher service account permission to publish to the topic. Grant the Firebase Functions runtime service account permission to subscribe/read from the subscription attached to that topic.
9. Create a push subscription on the topic that delivers to the deployed `billingRtdn` HTTPS function, or use a small Pub/Sub-triggered adapter that forwards the authenticated message to that function. Keep the Pub/Sub push subscription authenticated in production.
10. Deploy a test build and trigger Google's RTDN test notification. Confirm a document is written to `billingRtdn`, the notification is deduplicated by `messageId`, and the corresponding business entitlement is refreshed through `purchases.subscriptionsv2.get`.

## Google Cloud service account and API access

1. In the linked Google Cloud project, enable **Google Play Android Developer API** and **Pub/Sub API**.
2. Create or use the Firebase Functions runtime service account. Do not place a JSON key in the Flutter app, repository or `dart-define` values.
3. In Play Console **Users and permissions**, invite that service account email as a developer account with the minimum permission needed to view subscription and order information and manage subscriptions/purchases as required by the verification and acknowledgement calls. Prefer a dedicated service account and least privilege.
4. Deploy Functions with Application Default Credentials. `googleapis` uses the runtime service account to call `androidpublisher.purchases.subscriptionsv2.get` and acknowledge verified purchases.
5. Set `PLAY_PACKAGE_NAME=duka.pos` in the Functions environment if the production application ID differs from the development default.
6. Require a Firebase ID token on `billingVerify`. Before production, finish the TODO in `billing.js` that checks that the authenticated UID is a member of the requested `businesses/{businessId}` document.

## Client configuration and deployment

Build the Flutter app with the deployed HTTPS Functions base URL and the signed-in business ID supplied by the app's authentication/session layer:

```bash
flutter build appbundle --release \
  --dart-define=BILLING_API_BASE_URL=https://REGION-PROJECT.cloudfunctions.net \
  --dart-define=DUKAPOS_BUSINESS_ID=BUSINESS_ID
```

The current port has the paywall under **More > Plans & billing**. It loads localized prices from Google Play, supports monthly/annual switching, restore purchases, pending/error states, server-only verification messaging, and terms/privacy links. Replace the placeholder terms and privacy URLs in `lib/billing/paywall.dart` before submission. The client calls the deployed `billingCatalog` and `billingVerify` HTTPS functions. Wire `HttpBillingApi.authTokenProvider` to the Firebase Auth user's current ID token before production; the server rejects verification requests without a bearer token.

## Entitlement and offline behavior

The entitlement cache is stored in `SharedPreferences` only as a last-known server result. It is not treated as proof of a new purchase. During a connectivity outage, a recently verified paid entitlement receives a seven-day grace period. After that, the app falls back to Free-tier limits and can mark paid-only areas read-only; it never blocks offline selling, receipt creation or access to older local data.

A canceled or expired plan is not deleted locally. The app can still sell under Free limits, while paid-only features degrade gracefully. Renewals, cancellations, refunds, grace period, account hold, pause and recovery are reconciled by RTDN followed by a fresh Developer API lookup.

## Verification lifecycle

`billingVerify` records the purchase token mapping, retrieves the subscription with the Google Play Developer API, determines the current `subscriptionState`, writes the business entitlement, and acknowledges a verified non-pending purchase. `billingRtdn` decodes the Pub/Sub message, deduplicates by `messageId`, finds the business by token hash, and calls the same verification path. RTDN is treated as a signal only; it does not contain enough information to grant access by itself. The admin support surface is represented by the admin-only `listBillingBusinesses` and `setBillingOverride` callables; connect these to the support panel without exposing either callable to ordinary business members.

The server supports upgrades and downgrades by accepting the new token, storing the `linkedPurchaseToken`, and refreshing the new subscription resource. The old token must not be used to keep paid access after its expiry. Pending purchases do not grant access until Play reports a completed purchase.

## Admin overrides

`setBillingOverride` is a callable Function restricted to a Firebase custom `admin` claim. It writes `source: admin_override`, an explicit reason, the operator UID and optional expiry to the business record. An admin web panel can call this function and display `businesses/{businessId}.billing`; do not expose a client-write path for overrides.

## Automated tests

The Flutter tests cover the payment-independent domain and UI smoke path. Add mocked `BillingApi` tests before release for:

- active, grace-period, account-hold, expired and revoked server responses;
- malformed and rejected purchase tokens;
- pending, failed, restored and upgraded purchase-stream responses;
- seven-day offline grace and Free-tier fallback;
- duplicate RTDN `messageId` handling;
- linked purchase tokens for upgrade/downgrade;
- manual admin override expiry.

Run:

```bash
flutter pub get
flutter test
flutter analyze
```

## Optional direct M-Pesa subscriptions

TODO: keep the direct M-Pesa subscription route disabled by default. Before enabling it, review the current Google Play Payments policy and regional alternative-billing requirements with legal/product counsel. The existing DukaPOS M-Pesa adapter remains for retail payment collection and must not be treated as a replacement for Play Billing for digital subscription access unless the applicable Play policy explicitly permits the flow.

## References

- [1]: https://pub.dev/packages/in_app_purchase "Flutter in_app_purchase package"
- [2]: https://developer.android.com/google/play/billing/release-notes "Google Play Billing Library release notes"
- [3]: https://developer.android.com/google/play/billing/rtdn-reference "Real-time developer notifications reference"
- [4]: https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2 "Google Play Developer API Subscription Purchase V2"
- [5]: https://developer.android.com/google/play/billing/subscriptions "Google Play subscriptions lifecycle"
- [6]: https://support.google.com/googleplay/android-developer/answer/10281818?hl=en "Google Play Payments policy"
