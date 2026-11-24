import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/app_database.dart';
import 'domain/pos.dart';

class AppController extends ChangeNotifier {
  AppController(this.db);
  final AppDatabase db;
  StreamSubscription<List<Product>>? _productsSubscription;
  List<ProductModel> products = demoProducts;
  final List<CartLine> cart = [];
  int pendingSync = 0;
  int todaySalesKes = 0;
  int transactionCount = 0;
  String language = 'en';
  String? lastReceipt;
  int? lastTotal;
  int? lastChange;
  bool loaded = false;
  String mpesaTillNumber = '';
  String mpesaPaybillNumber = '';
  String mpesaAccountReference = 'DUKAPOS';

  SaleSummary get summary => calculateSummary(cart);
  List<String> get categories => [
    'All',
    ...{...products.map((item) => item.category)},
  ];

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    mpesaTillNumber = preferences.getString('mpesa.till') ?? '';
    mpesaPaybillNumber = preferences.getString('mpesa.paybill') ?? '';
    mpesaAccountReference =
        preferences.getString('mpesa.reference') ?? 'DUKAPOS';
    await db.seedProducts(
      demoProducts
          .map(
            (item) => ProductsCompanion.insert(
              id: item.id,
              name: item.name,
              category: item.category,
              priceKes: item.priceKes,
              costKes: item.costKes,
              stock: item.stock,
              lowStockThreshold: item.lowStockThreshold,
              updatedAt: DateTime.now(),
            ),
          )
          .toList(),
    );
    final rows = await db.allProducts();
    products = rows
        .map(
          (row) => ProductModel(
            id: row.id,
            name: row.name,
            category: row.category,
            unit: row.unit,
            priceKes: row.priceKes,
            costKes: row.costKes,
            stock: row.stock,
            lowStockThreshold: row.lowStockThreshold,
            barcode: row.barcode,
          ),
        )
        .toList();
    pendingSync = await db.pendingSyncCount();
    loaded = true;
    notifyListeners();
    _productsSubscription = db.watchProducts().listen((rows) {
      products = rows
          .map(
            (row) => ProductModel(
              id: row.id,
              name: row.name,
              category: row.category,
              unit: row.unit,
              priceKes: row.priceKes,
              costKes: row.costKes,
              stock: row.stock,
              lowStockThreshold: row.lowStockThreshold,
              barcode: row.barcode,
            ),
          )
          .toList();
      notifyListeners();
    });
  }

  void addToCart(ProductModel product) {
    final index = cart.indexWhere((line) => line.productId == product.id);
    if (index == -1) {
      cart.add(
        CartLine(
          productId: product.id,
          label: product.name,
          unitPriceKes: product.priceKes,
          unitCostKes: product.costKes,
          quantity: 1,
        ),
      );
    } else {
      final line = cart[index];
      cart[index] = CartLine(
        productId: line.productId,
        label: line.label,
        unitPriceKes: line.unitPriceKes,
        unitCostKes: line.unitCostKes,
        quantity: line.quantity + 1,
      );
    }
    notifyListeners();
  }

  void setQuantity(CartLine line, int quantity) {
    final index = cart.indexOf(line);
    if (index == -1) return;
    if (quantity <= 0) {
      cart.removeAt(index);
    } else {
      cart[index] = CartLine(
        productId: line.productId,
        label: line.label,
        unitPriceKes: line.unitPriceKes,
        unitCostKes: line.unitCostKes,
        quantity: quantity,
        vatRate: line.vatRate,
        isQuickSale: line.isQuickSale,
      );
    }
    notifyListeners();
  }

  Future<void> saveMpesaSettings({
    String? till,
    String? paybill,
    String? reference,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (till != null) {
      mpesaTillNumber = till.trim();
      await preferences.setString('mpesa.till', mpesaTillNumber);
    }
    if (paybill != null) {
      mpesaPaybillNumber = paybill.trim();
      await preferences.setString('mpesa.paybill', mpesaPaybillNumber);
    }
    if (reference != null) {
      mpesaAccountReference = reference.trim().isEmpty
          ? 'DUKAPOS'
          : reference.trim();
      await preferences.setString('mpesa.reference', mpesaAccountReference);
    }
    notifyListeners();
  }

  void addQuickSale(int amount) {
    if (amount <= 0) return;
    cart.add(
      CartLine(
        label: 'Quick sale',
        unitPriceKes: amount,
        unitCostKes: 0,
        quantity: 1,
        isQuickSale: true,
      ),
    );
    notifyListeners();
  }

  Future<void> completeSale(String paymentMethod, {int receivedKes = 0}) async {
    if (cart.isEmpty) return;
    final now = DateTime.now();
    final id = 'sale_${now.microsecondsSinceEpoch}';
    final receipt =
        'R-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(now.millisecond % 999).toString().padLeft(3, '0')}';
    final sale = SalesCompanion.insert(
      id: id,
      receiptNumber: receipt,
      subtotalKes: summary.subtotalKes,
      discountKes: summary.discountKes,
      taxKes: summary.taxKes,
      totalKes: summary.totalKes,
      paymentMethod: paymentMethod,
      createdAt: now,
    );
    final items = cart.asMap().entries.map((entry) {
      final line = entry.value;
      return SaleItemsCompanion.insert(
        id: '${id}_$entry.key',
        saleId: id,
        label: line.label,
        quantity: line.quantity,
        unitPriceKes: line.unitPriceKes,
        unitCostKes: line.unitCostKes,
        productId: drift.Value(line.productId),
      );
    }).toList();
    final deductions = <String, int>{};
    for (final line in cart) {
      if (line.productId != null) {
        deductions.update(
          line.productId!,
          (value) => value + line.quantity,
          ifAbsent: () => line.quantity,
        );
      }
    }
    await db.saveSale(sale: sale, items: items, stockDeductions: deductions);
    lastReceipt = receipt;
    lastTotal = summary.totalKes;
    lastChange = paymentMethod == 'Cash'
        ? calculateChange(summary.totalKes, receivedKes)
        : 0;
    todaySalesKes += summary.totalKes;
    transactionCount += 1;
    cart.clear();
    pendingSync = await db.pendingSyncCount();
    notifyListeners();
  }

  Future<void> adjustStock(
    ProductModel product,
    int delta,
    String reason,
  ) async {
    await db.adjustStock(product.id, delta, reason);
    pendingSync = await db.pendingSyncCount();
    notifyListeners();
  }

  Future<void> markSynced() async {
    await db.markAllSynced();
    pendingSync = await db.pendingSyncCount();
    notifyListeners();
  }

  @override
  void dispose() {
    _productsSubscription?.cancel();
    db.close();
    super.dispose();
  }
}
