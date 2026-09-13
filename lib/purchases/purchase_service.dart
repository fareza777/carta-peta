import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google Play one-time product used to remove every ad surface in CARTA.
///
/// The entitlement is only granted after the store reports `purchased` or
/// `restored`; a local flag then keeps the app useful offline and avoids an ad
/// while the store is temporarily unavailable.
class PurchaseService extends ChangeNotifier {
  PurchaseService({this.onAdsRemoved});

  static const productId = 'carta_remove_ads';
  static const storageKey = 'carta_remove_ads_v1';

  final Future<void> Function()? onAdsRemoved;
  final InAppPurchase _store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  ProductDetails? _product;
  bool _initialised = false;
  bool _available = false;
  bool _adsRemoved = false;
  bool _busy = false;
  String? _error;

  ProductDetails? get product => _product;
  bool get available => _available;
  bool get adsRemoved => _adsRemoved;
  bool get busy => _busy;
  String? get error => _error;

  Future<void> initialize() async {
    if (_initialised) return;
    _initialised = true;
    final prefs = await SharedPreferences.getInstance();
    _adsRemoved = prefs.getBool(storageKey) ?? false;
    if (_adsRemoved) {
      await onAdsRemoved?.call();
      notifyListeners();
    }

    _subscription = _store.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error) {
        _error = 'Google Play billing is temporarily unavailable.';
        _busy = false;
        notifyListeners();
        debugPrint('PurchaseService: purchase stream error: $error');
      },
    );

    try {
      _available = await _store.isAvailable();
      if (_available) {
        await _queryProduct();
        await _store.restorePurchases();
      }
    } on Exception catch (error) {
      debugPrint('PurchaseService: initialise failed: $error');
      _error = 'Google Play billing is temporarily unavailable.';
      notifyListeners();
    }
  }

  Future<void> _queryProduct() async {
    final response = await _store.queryProductDetails({productId});
    if (response.error != null) {
      _error = response.error!.message;
    }
    _product = response.productDetails
        .where((details) => details.id == productId)
        .firstOrNull;
    notifyListeners();
  }

  Future<void> buyRemoveAds() async {
    if (_busy || _adsRemoved) return;
    if (!_initialised) await initialize();
    final product = _product;
    if (!_available || product == null) {
      _error = 'Remove ads is not available yet. Please try again shortly.';
      notifyListeners();
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final started = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        _busy = false;
        _error = 'Google Play could not start the purchase.';
        notifyListeners();
      }
    } on Exception catch (error) {
      debugPrint('PurchaseService: purchase failed: $error');
      _busy = false;
      _error = 'Google Play could not start the purchase.';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    if (!_initialised) await initialize();
    if (!_available) {
      _error = 'Google Play billing is temporarily unavailable.';
      notifyListeners();
      return;
    }
    _error = null;
    notifyListeners();
    try {
      await _store.restorePurchases();
    } on Exception catch (error) {
      debugPrint('PurchaseService: restore failed: $error');
      _error = 'Could not restore purchases right now.';
      notifyListeners();
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != productId) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _grantRemoveAds();
        case PurchaseStatus.error:
          _error = purchase.error?.message ?? 'The purchase did not complete.';
          _busy = false;
          notifyListeners();
        case PurchaseStatus.canceled:
          _busy = false;
          notifyListeners();
        case PurchaseStatus.pending:
          _busy = true;
          notifyListeners();
      }
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
    }
  }

  Future<void> _grantRemoveAds() async {
    if (!_adsRemoved) {
      _adsRemoved = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(storageKey, true);
      await onAdsRemoved?.call();
    }
    _busy = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

extension on Iterable<ProductDetails> {
  ProductDetails? get firstOrNull => isEmpty ? null : first;
}
