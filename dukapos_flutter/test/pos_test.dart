import 'package:flutter_test/flutter_test.dart';
import 'package:dukapos_flutter/domain/pos.dart';

void main() {
  test('calculates VAT-inclusive KES totals', () {
    const line = CartLine(
      label: 'Milk',
      unitPriceKes: 70,
      unitCostKes: 54,
      quantity: 2,
      productId: 'milk',
    );
    final summary = calculateSummary([line]);
    expect(summary.subtotalKes, 140);
    expect(summary.taxKes, 22);
    expect(summary.totalKes, 162);
  });

  test('applies discount and calculates change without negative values', () {
    const line = CartLine(
      label: 'Bread',
      unitPriceKes: 75,
      unitCostKes: 58,
      quantity: 2,
      productId: 'bread',
    );
    final summary = calculateSummary([line], cartDiscountPercent: 10);
    expect(summary.discountKes, 15);
    expect(calculateChange(summary.totalKes, summary.totalKes + 100), 100);
    expect(calculateChange(summary.totalKes, 0), 0);
  });

  test('deducts stock but never below zero and ignores quick sales', () {
    final result = deductStock(demoProducts, const [
      CartLine(
        label: 'Sugar',
        unitPriceKes: 165,
        unitCostKes: 133,
        quantity: 20,
        productId: 'prod_sugar',
      ),
      CartLine(
        label: 'Quick',
        unitPriceKes: 500,
        unitCostKes: 0,
        quantity: 1,
        isQuickSale: true,
      ),
    ]);
    expect(result.singleWhere((p) => p.id == 'prod_sugar').stock, 0);
    expect(result.singleWhere((p) => p.id == 'prod_ugali').stock, 24);
  });

  test('formats Kenyan currency', () => expect(kes(123456), 'KES 123,456'));
}
