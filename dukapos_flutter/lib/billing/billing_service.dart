import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'billing_models.dart';

const _defaultBillingApiBaseUrl = String.fromEnvironment(
  'BILLING_API_BASE_URL',
);
const _defaultBusinessId = String.fromEnvironment('DUKAPOS_BUSINESS_ID');

abstract class BillingApi {
  Future<List<BillingPlan>> fetchPlans();
  Future<Entitlement> verifyPurchase({
    required String productId,
    required String purchaseToken,
  });
}

class HttpBillingApi implements BillingApi {
  HttpBillingApi({
    String? baseUrl,
    this.businessId = '',
    this.authTokenProvider,
  }) : baseUrl = baseUrl ?? _defaultBillingApiBaseUrl;
  final String baseUrl;
  final String businessId;
  final Future<String?> Function()? authTokenProvider;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<List<BillingPlan>> fetchPlans() async {
    if (baseUrl.isEmpty) return defaultBillingPlans;
    final response = await http.get(_uri('/billingCatalog'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Billing catalogue unavailable');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['plans'] as List<dynamic>)
        .map((item) => BillingPlan.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Entitlement> verifyPurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    if (baseUrl.isEmpty) {
      throw StateError('BILLING_API_BASE_URL is not configured');
    }
    final token = await authTokenProvider?.call();
    final headers = <String, String>{'content-type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }
    final response = await http.post(
      _uri('/billingVerify'),
      headers: headers,
      body: jsonEncode({
        'businessId': businessId,
        'productId': productId,
        'purchaseToken': purchaseToken,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Purchase verification failed');
    }
    return Entitlement.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

final defaultBillingPlans = <BillingPlan>[
  const BillingPlan(
    plan: 'free',
    productId: 'free',
    interval: 'forever',
    maxUsers: 1,
    maxBranches: 1,
    maxProducts: 100,
    features: {'reports': true, 'offlineSales': true},
    displayName: 'Free',
    description: '1 user · 1 branch · 100 products',
  ),
  const BillingPlan(
    plan: 'starter',
    productId: 'starter_monthly',
    interval: 'monthly',
    maxUsers: 2,
    maxBranches: 1,
    maxProducts: 1000,
    features: {'reports': true, 'customers': true, 'offlineSales': true},
    displayName: 'Starter',
    description: 'For a growing shop',
    targetPriceKsh: 300,
  ),
  const BillingPlan(
    plan: 'business',
    productId: 'business_monthly',
    interval: 'monthly',
    maxUsers: 5,
    maxBranches: 1,
    maxProducts: 5000,
    features: {
      'reports': true,
      'customers': true,
      'audit': true,
      'mpesa': true,
      'offlineSales': true,
    },
    displayName: 'Business',
    description: 'Controls for a busy store',
  ),
  const BillingPlan(
    plan: 'multibranch',
    productId: 'multibranch_monthly',
    interval: 'monthly',
    maxUsers: 25,
    maxBranches: 10,
    maxProducts: 20000,
    features: {
      'reports': true,
      'customers': true,
      'audit': true,
      'mpesa': true,
      'multibranch': true,
      'offlineSales': true,
    },
    displayName: 'Multi-branch',
    description: 'Central visibility across branches',
  ),
];

class BillingService extends ChangeNotifier {
  BillingService({
    BillingApi? api,
    this._preferences,
    String? businessId,
  }) : api =
           api ?? HttpBillingApi(businessId: businessId ?? _defaultBusinessId);
  final BillingApi api;
  SharedPreferences? _preferences;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  List<BillingPlan> plans = defaultBillingPlans;
  List<ProductDetails> products = [];
  Entitlement entitlement = Entitlement.free();
  bool storeAvailable = false;
  bool loading = false;
  String? error;

  Future<void> initialize() async {
    loading = true;
    notifyListeners();
    _preferences ??= await SharedPreferences.getInstance();
    final cached = _preferences!.getString('billing.entitlement');
    if (cached != null) entitlement = Entitlement.decode(cached);
    _purchaseSubscription ??= InAppPurchase.instance.purchaseStream.listen(
      _handlePurchases,
      onError: (Object value) => error = value.toString(),
    );
    storeAvailable = await InAppPurchase.instance.isAvailable();
    try {
      plans = await api.fetchPlans();
    } catch (_) {
      plans = defaultBillingPlans;
    }
    if (storeAvailable) {
      final response = await InAppPurchase.instance.queryProductDetails(
        subscriptionProductIds,
      );
      products = response.productDetails;
      if (response.error != null) error = response.error!.message;
    }
    loading = false;
    notifyListeners();
  }

  ProductDetails? productFor(String productId) =>
      products.where((item) => item.id == productId).firstOrNull;

  Future<void> purchase(ProductDetails product) async {
    error = null;
    notifyListeners();
    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<void> restorePurchases() => InAppPurchase.instance.restorePurchases();

  AccessDecision accessDecision(BillingPlan plan) {
    if (!entitlement.isPaid) {
      return AccessDecision(plan: 'free', readOnly: false, reason: 'Free tier');
    }
    if (entitlement.isActive) {
      return AccessDecision(
        plan: entitlement.plan,
        readOnly: false,
        reason: entitlement.status,
      );
    }
    if (entitlement.withinOfflineGrace) {
      return AccessDecision(
        plan: entitlement.plan,
        readOnly: false,
        reason: 'Offline verification grace period',
      );
    }
    return AccessDecision(
      plan: 'free',
      readOnly: true,
      reason: 'Paid entitlement could not be verified',
    );
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        error = 'Purchase pending. Access will update after Google Play confirms payment.';
        notifyListeners();
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        error = purchase.error?.message ?? 'Purchase failed';
        notifyListeners();
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          final token = purchase.verificationData.serverVerificationData;
          final verified = await api.verifyPurchase(
            productId: purchase.productID,
            purchaseToken: token,
          );
          entitlement = verified;
          await _preferences?.setString(
            'billing.entitlement',
            verified.encode(),
          );
          error = null;
          notifyListeners();
        } catch (_) {
          error = 'Purchase received but server verification is unavailable. No paid access was granted.';
          notifyListeners();
        }
      }
      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
