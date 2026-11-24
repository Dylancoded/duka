import 'dart:convert';

const subscriptionProductIds = <String>{
  'starter_monthly',
  'starter_annual',
  'business_monthly',
  'business_annual',
  'multibranch_monthly',
  'multibranch_annual',
};

class BillingPlan {
  const BillingPlan({
    required this.plan,
    required this.productId,
    required this.interval,
    required this.maxUsers,
    required this.maxBranches,
    required this.maxProducts,
    required this.features,
    this.displayName,
    this.description,
    this.targetPriceKsh,
  });

  final String plan;
  final String productId;
  final String interval;
  final int maxUsers;
  final int maxBranches;
  final int maxProducts;
  final Map<String, bool> features;
  final String? displayName;
  final String? description;

  /// Planning/reference price only. Google Play remains the price authority.
  final int? targetPriceKsh;

  factory BillingPlan.fromJson(Map<String, dynamic> json) => BillingPlan(
    plan: json['plan'] as String,
    productId: json['productId'] as String,
    interval: json['interval'] as String? ?? 'monthly',
    maxUsers: (json['maxUsers'] as num?)?.toInt() ?? 1,
    maxBranches: (json['maxBranches'] as num?)?.toInt() ?? 1,
    maxProducts: (json['maxProducts'] as num?)?.toInt() ?? 100,
    features: Map<String, bool>.from(json['features'] as Map? ?? const {}),
    displayName: json['displayName'] as String?,
    description: json['description'] as String?,
    targetPriceKsh: (json['targetPriceKsh'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'plan': plan,
    'productId': productId,
    'interval': interval,
    'maxUsers': maxUsers,
    'maxBranches': maxBranches,
    'maxProducts': maxProducts,
    'features': features,
    if (displayName != null) 'displayName': displayName,
    if (description != null) 'description': description,
    if (targetPriceKsh != null) 'targetPriceKsh': targetPriceKsh,
  };
}

class Entitlement {
  const Entitlement({
    required this.plan,
    required this.status,
    required this.expiresAt,
    required this.lastVerifiedAt,
    this.productId,
    this.purchaseToken,
    this.source = 'server',
    this.override = false,
  });

  final String plan;
  final String status;
  final DateTime? expiresAt;
  final DateTime lastVerifiedAt;
  final String? productId;
  final String? purchaseToken;
  final String source;
  final bool override;

  bool get isPaid => plan != 'free';
  bool get isActive => status == 'active' || status == 'grace_period';
  bool get withinOfflineGrace =>
      DateTime.now().isBefore(lastVerifiedAt.add(const Duration(days: 7)));

  Map<String, dynamic> toJson() => {
    'plan': plan,
    'status': status,
    'expiresAt': expiresAt?.toIso8601String(),
    'lastVerifiedAt': lastVerifiedAt.toIso8601String(),
    'productId': productId,
    'purchaseToken': purchaseToken,
    'source': source,
    'override': override,
  };

  factory Entitlement.fromJson(Map<String, dynamic> json) => Entitlement(
    plan: json['plan'] as String? ?? 'free',
    status: json['status'] as String? ?? 'unknown',
    expiresAt: json['expiresAt'] == null
        ? null
        : DateTime.tryParse(json['expiresAt'] as String),
    lastVerifiedAt:
        DateTime.tryParse(json['lastVerifiedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    productId: json['productId'] as String?,
    purchaseToken: json['purchaseToken'] as String?,
    source: json['source'] as String? ?? 'server',
    override: json['override'] as bool? ?? false,
  );

  String encode() => jsonEncode(toJson());
  static Entitlement decode(String value) =>
      Entitlement.fromJson(jsonDecode(value) as Map<String, dynamic>);

  static Entitlement free() => Entitlement(
    plan: 'free',
    status: 'active',
    expiresAt: null,
    lastVerifiedAt: DateTime.now(),
  );
}

class AccessDecision {
  const AccessDecision({
    required this.plan,
    required this.readOnly,
    required this.reason,
  });
  final String plan;
  final bool readOnly;
  final String reason;
}
