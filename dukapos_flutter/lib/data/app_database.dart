import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  TextColumn get unit => text().withDefault(const Constant('pcs'))();
  IntColumn get priceKes => integer()();
  IntColumn get costKes => integer()();
  IntColumn get stock => integer()();
  IntColumn get lowStockThreshold => integer()();
  TextColumn get barcode => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get receiptNumber => text()();
  IntColumn get subtotalKes => integer()();
  IntColumn get discountKes => integer()();
  IntColumn get taxKes => integer()();
  IntColumn get totalKes => integer()();
  TextColumn get paymentMethod => text()();
  TextColumn get customerId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text()();
  TextColumn get productId => text().nullable()();
  TextColumn get label => text()();
  IntColumn get quantity => integer()();
  IntColumn get unitPriceKes => integer()();
  IntColumn get unitCostKes => integer()();
  IntColumn get discountKes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Products, Sales, SaleItems, SyncQueue])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'dukapos_offline'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {},
  );

  Stream<List<Product>> watchProducts() => select(products).watch();
  Future<List<Product>> allProducts() => select(products).get();
  Future<Product?> productById(String id) =>
      (select(products)..where((row) => row.id.equals(id))).getSingleOrNull();
  Future<int> pendingSyncCount() async =>
      (select(syncQueue)..where((row) => row.status.equals('pending')))
          .get()
          .then((rows) => rows.length);

  Future<List<SyncQueueData>> pendingSyncEntries() =>
      (select(syncQueue)..where((row) => row.status.equals('pending'))).get();

  Future<void> markSyncEntrySynced(String id) =>
      (update(syncQueue)..where((row) => row.id.equals(id))).write(
        const SyncQueueCompanion(status: Value('synced')),
      );

  Future<void> markSyncEntryFailed(String id) =>
      (update(syncQueue)..where((row) => row.id.equals(id))).write(
        const SyncQueueCompanion(status: Value('failed')),
      );

  Future<void> retrySyncEntry(String id, int attempts) =>
      (update(syncQueue)..where((row) => row.id.equals(id))).write(
        SyncQueueCompanion(
          status: const Value('pending'),
          attempts: Value(attempts + 1),
        ),
      );

  Future<void> seedProducts(List<ProductsCompanion> rows) async {
    if ((await allProducts()).isNotEmpty) return;
    await batch((batch) => batch.insertAll(products, rows));
  }

  Future<void> saveSale({
    required SalesCompanion sale,
    required List<SaleItemsCompanion> items,
    required Map<String, int> stockDeductions,
  }) async {
    await transaction(() async {
      await into(sales).insert(sale);
      await batch((batch) => batch.insertAll(saleItems, items));
      for (final entry in stockDeductions.entries) {
        await customUpdate(
          'UPDATE products SET stock = MAX(0, stock - ?) WHERE id = ?',
          variables: [Variable<int>(entry.value), Variable<String>(entry.key)],
          updates: {products},
        );
      }
      await into(syncQueue).insert(
        SyncQueueCompanion.insert(
          id: sale.id.value,
          entity: 'sale',
          entityId: sale.id.value,
          operation: 'create',
          payloadJson: jsonEncode({
            'id': sale.id.value,
            'receiptNumber': sale.receiptNumber.value,
            'subtotalKes': sale.subtotalKes.value,
            'discountKes': sale.discountKes.value,
            'taxKes': sale.taxKes.value,
            'totalKes': sale.totalKes.value,
            'paymentMethod': sale.paymentMethod.value,
            'customerId': sale.customerId.value,
            'createdAt': sale.createdAt.value.toIso8601String(),
            'items': items
                .map(
                  (item) => {
                    'id': item.id.value,
                    'productId': item.productId.value,
                    'label': item.label.value,
                    'quantity': item.quantity.value,
                    'unitPriceKes': item.unitPriceKes.value,
                    'unitCostKes': item.unitCostKes.value,
                    'discountKes': item.discountKes.value,
                  },
                )
                .toList(),
          }),
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> adjustStock(String productId, int delta, String reason) async {
    await customUpdate(
      'UPDATE products SET stock = MAX(0, stock + ?), version = version + 1, updated_at = ? WHERE id = ?',
      variables: [
        Variable<int>(delta),
        Variable<DateTime>(DateTime.now()),
        Variable<String>(productId),
      ],
      updates: {products},
    );
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        id: 'stock_${DateTime.now().microsecondsSinceEpoch}',
        entity: 'product',
        entityId: productId,
        operation: 'update',
        payloadJson: jsonEncode({'delta': delta, 'reason': reason}),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> markAllSynced() async =>
      (update(syncQueue)..where((row) => row.status.equals('pending'))).write(
        const SyncQueueCompanion(status: Value('synced')),
      );
}
