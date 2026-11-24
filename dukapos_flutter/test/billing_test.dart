import 'package:flutter_test/flutter_test.dart';
import 'package:dukapos_flutter/billing/billing_models.dart';
import 'package:dukapos_flutter/billing/billing_service.dart';

class FakeBillingApi implements BillingApi {
  @override
  Future<List<BillingPlan>> fetchPlans() async => defaultBillingPlans;

  @override
  Future<Entitlement> verifyPurchase({
    required String productId,
    required String purchaseToken,
  }) async => Entitlement(
    plan: 'business',
    status: 'active',
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    lastVerifiedAt: DateTime.now(),
    productId: productId,
    purchaseToken: purchaseToken,
  );
}

void main() {
  test('remote plan JSON preserves feature flags and limits', () {
    final plan = BillingPlan.fromJson({
      'plan': 'business',
      'productId': 'business_monthly',
      'maxUsers': 5,
      'maxBranches': 1,
      'maxProducts': 5000,
      'features': {'audit': true, 'mpesa': false},
    });
    expect(plan.maxUsers, 5);
    expect(plan.features['audit'], isTrue);
    expect(plan.features['mpesa'], isFalse);
  });

  test('paid entitlement is active and does not require read-only mode', () {
    final service = BillingService(api: FakeBillingApi());
    service.entitlement = Entitlement(
      plan: 'business',
      status: 'active',
      expiresAt: DateTime.now().add(const Duration(days: 30)),
      lastVerifiedAt: DateTime.now(),
    );
    final decision = service.accessDecision(defaultBillingPlans[2]);
    expect(decision.plan, 'business');
    expect(decision.readOnly, isFalse);
    service.dispose();
  });

  test('verified entitlement receives seven-day offline grace', () {
    final service = BillingService(api: FakeBillingApi());
    service.entitlement = Entitlement(
      plan: 'starter',
      status: 'expired',
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      lastVerifiedAt: DateTime.now().subtract(const Duration(days: 2)),
    );
    final decision = service.accessDecision(defaultBillingPlans[1]);
    expect(decision.plan, 'starter');
    expect(decision.readOnly, isFalse);
    service.dispose();
  });

  test('old entitlement falls back to free read-only mode after grace', () {
    final service = BillingService(api: FakeBillingApi());
    service.entitlement = Entitlement(
      plan: 'starter',
      status: 'expired',
      expiresAt: DateTime.now().subtract(const Duration(days: 10)),
      lastVerifiedAt: DateTime.now().subtract(const Duration(days: 8)),
    );
    final decision = service.accessDecision(defaultBillingPlans[1]);
    expect(decision.plan, 'free');
    expect(decision.readOnly, isTrue);
    service.dispose();
  });
}
