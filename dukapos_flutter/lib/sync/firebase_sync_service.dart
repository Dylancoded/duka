import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../data/app_database.dart';
import '../firebase_bootstrap.dart';

class FirebaseSyncResult {
  const FirebaseSyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}

/// Replicates local Drift changes to Firestore.
///
/// Drift remains the source of truth for the cashier UI. A queue entry is only
/// acknowledged after the corresponding Firestore write succeeds. Document
/// IDs are stable, so retries are safe and do not create duplicate sales.
class FirebaseSyncService {
  FirebaseSyncService({required this.database, required this.businessId});

  final AppDatabase database;
  final String businessId;

  Future<FirebaseSyncResult> syncPending() async {
    if (!FirebaseBootstrap.initialized || businessId.trim().isEmpty) {
      return const FirebaseSyncResult(synced: 0, failed: 0);
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.isEmpty ||
        connectivity.every((result) => result == ConnectivityResult.none)) {
      return const FirebaseSyncResult(synced: 0, failed: 0);
    }

    var synced = 0;
    var failed = 0;
    for (final entry in await database.pendingSyncEntries()) {
      try {
        await _upload(entry);
        await database.markSyncEntrySynced(entry.id);
        synced++;
      } catch (_) {
        failed++;
        await database.retrySyncEntry(entry.id, entry.attempts);
      }
    }
    return FirebaseSyncResult(synced: synced, failed: failed);
  }

  Future<void> _upload(SyncQueueData entry) async {
    final payload = Map<String, dynamic>.from(
      jsonDecode(entry.payloadJson) as Map,
    );
    final root = FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId);

    if (entry.entity == 'sale') {
      final saleId = entry.entityId;
      final items = (payload.remove('items') as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      payload['updatedAt'] = FieldValue.serverTimestamp();
      payload['syncOperationId'] = entry.id;
      payload['items'] = items;
      await root
          .collection('sales')
          .doc(saleId)
          .set(payload, SetOptions(merge: true));
      return;
    }

    if (entry.entity == 'product') {
      final product = await database.productById(entry.entityId);
      if (product == null) return;
      await root.collection('products').doc(product.id).set({
        'id': product.id,
        'name': product.name,
        'category': product.category,
        'unit': product.unit,
        'priceKes': product.priceKes,
        'costKes': product.costKes,
        'stock': product.stock,
        'lowStockThreshold': product.lowStockThreshold,
        'barcode': product.barcode,
        'version': product.version,
        'updatedAt': Timestamp.fromDate(product.updatedAt),
        'syncOperationId': entry.id,
      }, SetOptions(merge: true));
      return;
    }

    await root.collection('syncQueue').doc(entry.id).set({
      'entity': entry.entity,
      'entityId': entry.entityId,
      'operation': entry.operation,
      'payload': payload,
      'createdAt': Timestamp.fromDate(entry.createdAt),
    }, SetOptions(merge: true));
  }
}
