import 'dart:math' as math;

class ProductModel {
  const ProductModel({
    required this.id,
    required this.name,
    required this.category,
    required this.priceKes,
    required this.costKes,
    required this.stock,
    required this.lowStockThreshold,
    this.unit = 'pcs',
    this.barcode,
  });
  final String id;
  final String name;
  final String category;
  final String unit;
  final int priceKes;
  final int costKes;
  final int stock;
  final int lowStockThreshold;
  final String? barcode;

  bool get lowStock => stock <= lowStockThreshold;
  ProductModel copyWith({int? stock}) => ProductModel(
    id: id,
    name: name,
    category: category,
    priceKes: priceKes,
    costKes: costKes,
    stock: stock ?? this.stock,
    lowStockThreshold: lowStockThreshold,
    unit: unit,
    barcode: barcode,
  );
}

class CartLine {
  const CartLine({
    required this.label,
    required this.unitPriceKes,
    required this.unitCostKes,
    required this.quantity,
    this.productId,
    this.vatRate = .16,
    this.isQuickSale = false,
  });
  final String? productId;
  final String label;
  final int unitPriceKes;
  final int unitCostKes;
  final int quantity;
  final double vatRate;
  final bool isQuickSale;
  int get grossKes => unitPriceKes * quantity;
}

class SaleSummary {
  const SaleSummary({
    required this.subtotalKes,
    required this.discountKes,
    required this.taxKes,
    required this.totalKes,
  });
  final int subtotalKes;
  final int discountKes;
  final int taxKes;
  final int totalKes;
}

SaleSummary calculateSummary(
  List<CartLine> lines, {
  double cartDiscountPercent = 0,
  bool vatEnabled = true,
}) {
  final subtotal = lines.fold<int>(0, (sum, line) => sum + line.grossKes);
  final cartDiscount = ((subtotal * cartDiscountPercent.clamp(0, 100)) / 100)
      .round();
  final taxable = math.max(0, subtotal - cartDiscount);
  final tax = vatEnabled
      ? lines.fold<int>(
          0,
          (sum, line) =>
              sum +
              ((line.grossKes * line.vatRate) * (1 - cartDiscountPercent / 100))
                  .round(),
        )
      : 0;
  return SaleSummary(
    subtotalKes: subtotal,
    discountKes: cartDiscount,
    taxKes: tax,
    totalKes: taxable + tax,
  );
}

int calculateChange(int totalKes, int receivedKes) =>
    math.max(0, receivedKes - totalKes);

List<ProductModel> deductStock(
  List<ProductModel> products,
  List<CartLine> lines,
) {
  final quantities = <String, int>{};
  for (final line in lines) {
    if (line.productId != null && !line.isQuickSale) {
      quantities.update(
        line.productId!,
        (value) => value + line.quantity,
        ifAbsent: () => line.quantity,
      );
    }
  }
  return products
      .map(
        (product) => quantities.containsKey(product.id)
            ? product.copyWith(
                stock: math.max(0, product.stock - quantities[product.id]!),
              )
            : product,
      )
      .toList();
}

String kes(int amount) =>
    'KES ${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match.group(1)},')}';

List<ProductModel> demoProducts = const [
  ProductModel(
    id: 'prod_ugali',
    name: 'Unga wa Ugali 2kg',
    category: 'Groceries',
    priceKes: 180,
    costKes: 145,
    stock: 24,
    lowStockThreshold: 8,
  ),
  ProductModel(
    id: 'prod_milk',
    name: 'Brookside Milk 500ml',
    category: 'Dairy',
    priceKes: 70,
    costKes: 54,
    stock: 18,
    lowStockThreshold: 6,
  ),
  ProductModel(
    id: 'prod_bread',
    name: 'Broadways Bread',
    category: 'Bakery',
    priceKes: 75,
    costKes: 58,
    stock: 11,
    lowStockThreshold: 5,
  ),
  ProductModel(
    id: 'prod_soda',
    name: 'Coca-Cola 500ml',
    category: 'Drinks',
    priceKes: 80,
    costKes: 52,
    stock: 32,
    lowStockThreshold: 10,
  ),
  ProductModel(
    id: 'prod_sugar',
    name: 'Kabras Sugar 1kg',
    category: 'Groceries',
    priceKes: 165,
    costKes: 133,
    stock: 7,
    lowStockThreshold: 8,
  ),
  ProductModel(
    id: 'prod_soap',
    name: 'Geisha Bar Soap',
    category: 'Household',
    priceKes: 95,
    costKes: 68,
    stock: 15,
    lowStockThreshold: 5,
  ),
];
