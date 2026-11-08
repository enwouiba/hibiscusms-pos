import 'product.dart';

/// Liy nan kart pandan POS (volatile — pa nan SQLite).
class CartItem {
  final Product product;
  final double quantity;
  final double discount;

  const CartItem({
    required this.product,
    this.quantity = 1,
    this.discount = 0,
  });

  double get unitPrice => product.price;
  double get subtotal => unitPrice * quantity - discount;
  double get taxAmount => subtotal * product.taxRate / 100;

  CartItem copyWith({double? quantity, double? discount}) => CartItem(
        product: product,
        quantity: quantity ?? this.quantity,
        discount: discount ?? this.discount,
      );
}
