import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/cart_item.dart';
import '../../../shared/models/product.dart';

class CartState {
  final List<CartItem> items;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final double customerBalance; // ≥ 0 means owed by customer (debt)
  final double extraDiscount;

  const CartState({
    this.items = const [],
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerBalance = 0,
    this.extraDiscount = 0,
  });

  double get subtotal => items.fold(0, (s, i) => s + i.subtotal);
  double get taxTotal => items.fold(0, (s, i) => s + i.taxAmount);
  double get grandTotal =>
      (subtotal - extraDiscount + taxTotal).clamp(0, double.infinity).toDouble();
  int get itemCount => items.fold<int>(0, (s, i) => s + i.quantity.ceil());
  bool get isEmpty => items.isEmpty;

  CartState copyWith({
    List<CartItem>? items,
    String? customerId,
    String? customerName,
    String? customerPhone,
    double? customerBalance,
    double? extraDiscount,
    bool clearCustomer = false,
  }) =>
      CartState(
        items: items ?? this.items,
        customerId: clearCustomer ? null : (customerId ?? this.customerId),
        customerName: clearCustomer ? null : (customerName ?? this.customerName),
        customerPhone: clearCustomer ? null : (customerPhone ?? this.customerPhone),
        customerBalance: clearCustomer ? 0 : (customerBalance ?? this.customerBalance),
        extraDiscount: extraDiscount ?? this.extraDiscount,
      );
}

class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void addProduct(Product p, {double quantity = 1}) {
    final idx = state.items.indexWhere((c) => c.product.id == p.id);
    final newItems = [...state.items];
    if (idx >= 0) {
      newItems[idx] = newItems[idx].copyWith(quantity: newItems[idx].quantity + quantity);
    } else {
      newItems.add(CartItem(product: p, quantity: quantity));
    }
    state = state.copyWith(items: newItems);
  }

  void setQuantity(String productId, double quantity) {
    if (quantity <= 0) {
      remove(productId);
      return;
    }
    final newItems = state.items
        .map((c) => c.product.id == productId ? c.copyWith(quantity: quantity) : c)
        .toList();
    state = state.copyWith(items: newItems);
  }

  void setItemDiscount(String productId, double discount) {
    final newItems = state.items
        .map((c) => c.product.id == productId ? c.copyWith(discount: discount) : c)
        .toList();
    state = state.copyWith(items: newItems);
  }

  void remove(String productId) {
    state = state.copyWith(items: state.items.where((c) => c.product.id != productId).toList());
  }

  void setCustomer({String? id, String? name, String? phone, double balance = 0}) {
    if (id == null && (name == null || name.isEmpty)) {
      state = state.copyWith(clearCustomer: true);
    } else {
      state = state.copyWith(
        customerId: id,
        customerName: name,
        customerPhone: phone,
        customerBalance: balance,
      );
    }
  }

  /// Use this when the cashier types a fresh name without picking an existing
  /// customer — keeps the typed name in cart but no id (sale_repository will
  /// auto-create the customer at confirm time).
  void setNewCustomerName(String name, {String? phone}) {
    if (name.trim().isEmpty) {
      state = state.copyWith(clearCustomer: true);
    } else {
      state = state.copyWith(
        customerId: null,
        customerName: name.trim(),
        customerPhone: (phone ?? '').trim().isEmpty ? null : phone!.trim(),
        customerBalance: 0,
      );
    }
  }

  void setDiscount(double d) {
    state = state.copyWith(extraDiscount: d);
  }

  void clear() {
    state = const CartState();
  }
}

final cartProvider = NotifierProvider<CartController, CartState>(CartController.new);
