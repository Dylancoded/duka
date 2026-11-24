import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app_controller.dart';
import 'billing/billing_service.dart';
import 'billing/paywall.dart';
import 'data/app_database.dart';
import 'domain/pos.dart';
import 'firebase_bootstrap.dart';
import 'sync/firebase_sync_service.dart';

void main() => runApp(const DukaPosApp());

class DukaPosApp extends StatefulWidget {
  const DukaPosApp({super.key});
  @override
  State<DukaPosApp> createState() => _DukaPosAppState();
}

class _DukaPosAppState extends State<DukaPosApp> {
  late final AppController controller;
  late final BillingService billing;
  Timer? syncTimer;
  @override
  void initState() {
    super.initState();
    controller = AppController(AppDatabase())..load();
    billing = BillingService()..initialize();
    _startFirebaseSync();
  }

  Future<void> _startFirebaseSync() async {
    final ready = await FirebaseBootstrap.initialize();
    if (!mounted || !ready) return;
    final service = FirebaseSyncService(
      database: controller.db,
      businessId: const String.fromEnvironment('DUKAPOS_BUSINESS_ID'),
    );
    await service.syncPending();
    syncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      service.syncPending();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    billing.dispose();
    syncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'DukaPOS',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D6B4B)),
      scaffoldBackgroundColor: const Color(0xFFF8F9F6),
    ),
    home: HomePage(controller, billing),
  );
}

class HomePage extends StatefulWidget {
  const HomePage(this.controller, this.billing, {super.key});
  final AppController controller;
  final BillingService billing;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: tab,
          children: [
            SellPage(widget.controller),
            ProductsPage(widget.controller),
            ReportsPage(widget.controller),
            MorePage(widget.controller, widget.billing),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Sell',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Products',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Reports',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    ),
  );
}

class SellPage extends StatefulWidget {
  const SellPage(this.c, {super.key});
  final AppController c;
  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> {
  String query = '';
  String category = 'All';
  @override
  Widget build(BuildContext context) {
    final products = widget.c.products
        .where(
          (p) =>
              (category == 'All' || p.category == category) &&
              p.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Sell',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
              ),
            ),
            Chip(
              label: Text(
                widget.c.pendingSync == 0
                    ? 'Synced'
                    : '${widget.c.pendingSync} to sync',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search products or scan barcode',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.c.categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final x = widget.c.categories[i];
              return FilterChip(
                label: Text(x),
                selected: x == category,
                onSelected: (_) => setState(() => category = x),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 140,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: products.length,
          itemBuilder: (_, i) =>
              ProductTile(products[i], () => widget.c.addToCart(products[i])),
        ),
        const SizedBox(height: 16),
        CartCard(widget.c, () => checkout(context)),
      ],
    );
  }

  Future<void> checkout(BuildContext context) async {
    final total = widget.c.summary.totalKes;
    final method = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Payment method'),
        children: ['Cash', 'M-Pesa', 'Credit']
            .map(
              (x) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, x),
                child: Text(x),
              ),
            )
            .toList(),
      ),
    );
    if (method == null) return;
    var recordedMethod = method;
    if (method == 'M-Pesa') {
      final rail = await _showMpesaPrompt(context, total);
      if (rail == null) return;
      recordedMethod = 'M-Pesa $rail';
    }
    await widget.c.completeSale(recordedMethod, receivedKes: total);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sale complete: ${kes(total)}')));
    }
  }

  Future<String?> _showMpesaPrompt(BuildContext context, int total) async {
    var rail = widget.c.mpesaTillNumber.isNotEmpty ? 'Till' : 'Paybill';
    return showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Prompt customer to pay M-Pesa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ask the customer to pay ${kes(total)} and show the confirmation message before completing the sale.',
              ),
              const SizedBox(height: 12),
              if (widget.c.mpesaTillNumber.isNotEmpty)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'Till',
                  groupValue: rail,
                  onChanged: (value) => setDialogState(() => rail = value!),
                  title: Text('Till ${widget.c.mpesaTillNumber}'),
                  subtitle: const Text('Buy Goods and Services'),
                ),
              if (widget.c.mpesaPaybillNumber.isNotEmpty)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'Paybill',
                  groupValue: rail,
                  onChanged: (value) => setDialogState(() => rail = value!),
                  title: Text('Paybill ${widget.c.mpesaPaybillNumber}'),
                  subtitle: Text('Account: ${widget.c.mpesaAccountReference}'),
                ),
              if (widget.c.mpesaTillNumber.isEmpty &&
                  widget.c.mpesaPaybillNumber.isEmpty)
                const Text(
                  'Set the merchant Till or Paybill number in More → M-Pesa settings first.',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  widget.c.mpesaTillNumber.isEmpty &&
                      widget.c.mpesaPaybillNumber.isEmpty
                  ? null
                  : () => Navigator.pop(dialog, rail),
              child: const Text('Customer has paid'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductsPage extends StatefulWidget {
  const ProductsPage(this.c, {super.key});
  final AppController c;
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String query = '';
  bool lowOnly = false;
  @override
  Widget build(BuildContext context) {
    final list = widget.c.products
        .where(
          (p) =>
              p.name.toLowerCase().contains(query.toLowerCase()) &&
              (!lowOnly || p.lowStock),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const BrandHeader(),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Products',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Product creation form is ready for repository wiring.',
                  ),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search catalogue',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(18)),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 10),
        FilterChip(
          label: const Text('Low stock only'),
          selected: lowOnly,
          onSelected: (v) => setState(() => lowOnly = v),
        ),
        const SizedBox(height: 12),
        ...list.map(
          (p) => Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE7F4EE),
                child: Text(p.name[0]),
              ),
              title: Text(
                p.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${p.category} · ${p.stock} ${p.unit} · ${kes(p.priceKes)}',
              ),
              trailing: p.lowStock
                  ? const Icon(Icons.warning_amber, color: Colors.orange)
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage(this.c, {super.key});
  final AppController c;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const BrandHeader(),
      const SizedBox(height: 24),
      const Text(
        'Reports',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: StatCard(
              'Today sales',
              kes(c.todaySalesKes),
              Icons.payments,
              const Color(0xFFE7F4EE),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatCard(
              'Transactions',
              '${c.transactionCount}',
              Icons.receipt_long,
              const Color(0xFFFFF5DA),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: StatCard(
              'Low stock',
              '${c.products.where((p) => p.lowStock).length}',
              Icons.warning_amber,
              const Color(0xFFFFF5DA),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatCard(
              'To sync',
              '${c.pendingSync}',
              Icons.cloud_upload_outlined,
              const Color(0xFFE7F4EE),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      const Card(
        child: ListTile(
          leading: Icon(Icons.point_of_sale),
          title: Text('Cash reconciliation / Z-report'),
          subtitle: Text('Expected vs counted cash and audit trail'),
        ),
      ),
      const Card(
        child: ListTile(
          leading: Icon(Icons.download),
          title: Text('Export PDF / Excel'),
          subtitle: Text('Native document adapters are next in the port'),
        ),
      ),
    ],
  );
}

class MorePage extends StatelessWidget {
  const MorePage(this.c, this.billing, {super.key});
  final AppController c;
  final BillingService billing;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const BrandHeader(),
      const SizedBox(height: 24),
      const Text(
        'More',
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 16),
      Card(
        color: const Color(0xFF0D6B4B),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CURRENT PLAN', style: TextStyle(color: Colors.white70)),
              SizedBox(height: 5),
              Text(
                'Free',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '1 branch · 1 user · up to 100 products',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('Plans & billing'),
          subtitle: Text(
            '${billing.entitlement.plan} plan · server verified access',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SubscriptionPaywall(billing: billing),
            ),
          ),
        ),
      ),
      const MoreTile(
        Icons.people_alt_outlined,
        'Customers & debtors',
        'Balances, points and consent',
      ),
      const MoreTile(
        Icons.receipt_long_outlined,
        'Expenses',
        'Daily costs by category',
      ),
      const MoreTile(
        Icons.badge_outlined,
        'Staff & audit',
        'Roles, shifts and manager approvals',
      ),
      const MoreTile(
        Icons.hub_outlined,
        'Integrations',
        'eTIMS queue and M-Pesa setup',
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.phone_android),
          title: const Text('M-Pesa Till / Paybill'),
          subtitle: Text(
            c.mpesaTillNumber.isNotEmpty
                ? 'Till ${c.mpesaTillNumber}'
                : c.mpesaPaybillNumber.isNotEmpty
                ? 'Paybill ${c.mpesaPaybillNumber}'
                : 'Not configured',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editMpesaSettings(context),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Sync now'),
          subtitle: Text('${c.pendingSync} operations pending'),
          onTap: c.markSynced,
        ),
      ),
      const Center(
        child: Text(
          'DukaPOS v0.1 · Offline-first Flutter port',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    ],
  );

  Future<void> _editMpesaSettings(BuildContext context) async {
    final till = TextEditingController(text: c.mpesaTillNumber);
    final paybill = TextEditingController(text: c.mpesaPaybillNumber);
    final reference = TextEditingController(text: c.mpesaAccountReference);
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('M-Pesa customer payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the merchant numbers customers should use. Keep Daraja credentials on the server.',
              ),
              TextField(
                controller: till,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Till number (Buy Goods)',
                ),
              ),
              TextField(
                controller: paybill,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Paybill number'),
              ),
              TextField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'Paybill account/reference',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await c.saveMpesaSettings(
                till: till.text,
                paybill: paybill.text,
                reference: reference.text,
              );
              if (dialog.mounted) Navigator.pop(dialog);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    till.dispose();
    paybill.dispose();
    reference.dispose();
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      CircleAvatar(
        radius: 22,
        backgroundColor: Color(0xFFE7F4EE),
        child: Icon(Icons.receipt_long, color: Color(0xFF0D6B4B)),
      ),
      SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MWANGAZA MINI MART',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF0D6B4B),
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            'Main branch · Offline ready',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    ],
  );
}

class ProductTile extends StatelessWidget {
  const ProductTile(this.p, this.onTap, {super.key});
  final ProductModel p;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: const Color(0xFFE7F4EE),
              child: Text(p.name[0]),
            ),
            const Spacer(),
            Text(
              p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  kes(p.priceKes),
                  style: const TextStyle(
                    color: Color(0xFF0D6B4B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${p.stock} left',
                  style: TextStyle(
                    fontSize: 11,
                    color: p.lowStock ? Colors.orange : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class CartCard extends StatelessWidget {
  const CartCard(this.c, this.checkout, {super.key});
  final AppController c;
  final VoidCallback checkout;
  @override
  Widget build(BuildContext context) {
    final count = c.cart.fold<int>(0, (s, x) => s + x.quantity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Cart · $count items',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (c.cart.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      c.cart.clear();
                      c.notifyListeners();
                    },
                    child: const Text('Clear'),
                  ),
              ],
            ),
            if (c.cart.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Your cart is ready — tap a product to add it.'),
              )
            else
              ...c.cart.map(
                (line) => Row(
                  children: [
                    Expanded(child: Text(line.label)),
                    IconButton(
                      onPressed: () => c.setQuantity(line, line.quantity - 1),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('${line.quantity}'),
                    IconButton(
                      onPressed: () => c.setQuantity(line, line.quantity + 1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    SizedBox(
                      width: 75,
                      child: Text(
                        kes(line.grossKes),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            if (c.cart.isNotEmpty) ...[
              const Divider(),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    kes(c.summary.totalKes),
                    style: const TextStyle(
                      fontSize: 24,
                      color: Color(0xFF0D6B4B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: checkout,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Checkout'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard(this.label, this.value, this.icon, this.color, {super.key});
  final String label, value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0D6B4B)),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class MoreTile extends StatelessWidget {
  const MoreTile(this.icon, this.title, this.subtitle, {super.key});
  final IconData icon;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE7F4EE),
        child: Icon(icon, color: const Color(0xFF0D6B4B)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}
