import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'billing_service.dart';

class SubscriptionPaywall extends StatefulWidget {
  const SubscriptionPaywall({required this.billing, super.key});
  final BillingService billing;
  @override
  State<SubscriptionPaywall> createState() => _SubscriptionPaywallState();
}

class _SubscriptionPaywallState extends State<SubscriptionPaywall> {
  bool annual = false;
  String selectedPlan = 'starter';

  BillingService get billing => widget.billing;
  String get productId => '${selectedPlan}_${annual ? 'annual' : 'monthly'}';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: billing,
    builder: (context, _) {
      final product = billing.productFor(productId);
      final plan =
          billing.plans
              .where(
                (item) =>
                    item.plan == selectedPlan &&
                    item.interval == (annual ? 'annual' : 'monthly'),
              )
              .firstOrNull ??
          billing.plans.firstWhere(
            (item) => item.plan == selectedPlan,
            orElse: () => defaultBillingPlans[1],
          );
      return Scaffold(
        appBar: AppBar(title: const Text('Plans & billing')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Keep selling. Grow when ready.',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Paid access is activated only after DukaPOS verifies the purchase on the server.',
            ),
            const SizedBox(height: 18),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Monthly')),
                ButtonSegment(value: true, label: Text('Annual')),
              ],
              selected: {annual},
              onSelectionChanged: (value) =>
                  setState(() => annual = value.first),
            ),
            const SizedBox(height: 18),
            ...[
              'starter',
              'business',
              'multibranch',
            ].map((name) => _planCard(context, name)),
            const SizedBox(height: 8),
            if (product != null)
              Card(
                color: const Color(0xFFE7F4EE),
                child: ListTile(
                  title: Text(
                    '${plan.displayName ?? plan.plan} · ${product.price}',
                  ),
                  subtitle: Text(
                    plan.description ??
                        'Localised price from Google Play${annual ? ' · annual billing' : ''}',
                  ),
                  trailing: FilledButton(
                    onPressed: billing.loading
                        ? null
                        : () => billing.purchase(product),
                    child: const Text('Subscribe'),
                  ),
                ),
              )
            else
              const Card(
                child: ListTile(
                  title: Text('Google Play prices unavailable'),
                  subtitle: Text(
                    'Use an internal test track or configure the products in Play Console.',
                  ),
                ),
              ),
            if (billing.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  billing.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: billing.storeAvailable
                  ? billing.restorePurchases
                  : null,
              icon: const Icon(Icons.restore),
              label: const Text('Restore purchases'),
            ),
            const SizedBox(height: 12),
            Text(
              'Free plan: 1 user · 1 branch · up to 100 products. Sales are never blocked by billing or connectivity.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              children: [
                TextButton(
                  onPressed: () => _open('https://dukapos.example/terms'),
                  child: const Text('Terms'),
                ),
                TextButton(
                  onPressed: () => _open('https://dukapos.example/privacy'),
                  child: const Text('Privacy'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _planCard(BuildContext context, String name) {
    final plan = billing.plans.firstWhere(
      (item) => item.plan == name,
      orElse: () => defaultBillingPlans[1],
    );
    return Card(
      child: RadioListTile<String>(
        value: name,
        groupValue: selectedPlan,
        onChanged: (value) => setState(() => selectedPlan = value!),
        title: Text(
          plan.displayName ?? name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(plan.description ?? ''),
        secondary: Text(
          '${plan.maxUsers} users\n${plan.maxBranches} branches',
          textAlign: TextAlign.right,
        ),
      ),
    );
  }

  Future<void> _open(String value) async {
    final uri = Uri.parse(value);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
