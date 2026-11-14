import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/store_picker_screen.dart';
import '../../features/plan/presentation/plans_screen.dart';
import '../../features/system_owner/presentation/system_owner_screen.dart';
import '../../features/tenant_apk/presentation/tenant_apk_screen.dart';
import '../../features/business/presentation/business_settings_screen.dart';
import '../../features/cash_sessions/presentation/cash_session_screen.dart';
import '../../features/customers/presentation/customer_form_screen.dart';
import '../../features/customers/presentation/customers_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/products/presentation/product_form_screen.dart';
import '../../features/dryclean/presentation/dryclean_new_order_screen.dart';
import '../../features/dryclean/presentation/dryclean_order_detail_screen.dart';
import '../../features/dryclean/presentation/dryclean_orders_screen.dart';
import '../../features/dryclean/presentation/dryclean_reports_screen.dart';
import '../../features/hotel/presentation/hotel_checkin_screen.dart';
import '../../features/hotel/presentation/hotel_proforma_screen.dart';
import '../../features/hotel/presentation/hotel_reports_screen.dart';
import '../../features/hotel/presentation/hotel_room_form_screen.dart';
import '../../features/hotel/presentation/hotel_rooms_screen.dart';
import '../../features/hotel/presentation/hotel_stay_detail_screen.dart';
import '../../features/hotel/presentation/hotel_stays_screen.dart';
import '../../features/products/presentation/products_screen.dart';
import '../../features/purchases/presentation/purchase_form_screen.dart';
import '../../features/purchases/presentation/purchases_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/sales/presentation/pos_screen.dart';
import '../../features/sales/presentation/receipt_screen.dart';
import '../../features/sales/presentation/sales_history_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/settings/presentation/printer_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/stock/presentation/stock_movements_screen.dart';
import '../../features/suppliers/presentation/supplier_form_screen.dart';
import '../../features/suppliers/presentation/suppliers_screen.dart';
import '../../features/users/presentation/user_form_screen.dart';
import '../../features/users/presentation/users_screen.dart';
import '../auth/auth_state.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      // Splash la kontwole sòti l poukont li (dire minimòm + sesyon chaje).
      if (state.matchedLocation == '/splash') return null;
      final auth = ref.read(authControllerProvider);
      if (auth.isLoading) return null;
      final session = auth.valueOrNull;
      final isPublic = state.matchedLocation == '/login' || state.matchedLocation == '/register';
      if (session == null) {
        return isPublic ? null : '/login';
      }
      if (isPublic) return '/';
      return null;
    },
    refreshListenable: _AuthRefresh(ref),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/choose-store', builder: (_, _) => const StorePickerScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),

      // Pwodwi
      GoRoute(path: '/products', builder: (_, _) => const ProductsScreen()),
      GoRoute(path: '/dryclean', builder: (_, _) => const DrycleanOrdersScreen()),
      GoRoute(path: '/dryclean/reports', builder: (_, _) => const DrycleanReportsScreen()),
      GoRoute(path: '/dryclean/new', builder: (_, _) => const DrycleanNewOrderScreen()),
      GoRoute(path: '/dryclean/:id', builder: (_, s) => DrycleanOrderDetailScreen(orderId: s.pathParameters['id']!)),
      // Otèl
      GoRoute(path: '/hotel', builder: (_, _) => const HotelRoomsScreen()),
      GoRoute(path: '/hotel/stays', builder: (_, _) => const HotelStaysScreen()),
      GoRoute(path: '/hotel/proforma', builder: (_, _) => const HotelProformaScreen()),
      GoRoute(path: '/hotel/reports', builder: (_, _) => const HotelReportsScreen()),
      GoRoute(path: '/hotel/room/new', builder: (_, _) => const HotelRoomFormScreen()),
      GoRoute(path: '/hotel/room/:id', builder: (_, s) => HotelRoomFormScreen(roomId: s.pathParameters['id'])),
      GoRoute(path: '/hotel/checkin/:roomId', builder: (_, s) => HotelCheckinScreen(roomId: s.pathParameters['roomId']!)),
      GoRoute(path: '/hotel/stay/:id', builder: (_, s) => HotelStayDetailScreen(stayId: s.pathParameters['id']!)),
      GoRoute(path: '/products/new', builder: (_, _) => const ProductFormScreen()),
      GoRoute(
        path: '/products/:id',
        builder: (_, state) => ProductFormScreen(productId: state.pathParameters['id']),
      ),

      // POS
      GoRoute(path: '/pos', builder: (_, _) => const PosScreen()),

      // Vant
      GoRoute(path: '/sales', builder: (_, _) => const SalesHistoryScreen()),
      GoRoute(
        path: '/sales/:id',
        builder: (_, state) => ReceiptScreen(saleId: state.pathParameters['id']!),
      ),

      // Kliyan
      GoRoute(path: '/customers', builder: (_, _) => const CustomersScreen()),
      GoRoute(path: '/customers/new', builder: (_, _) => const CustomerFormScreen()),
      GoRoute(
        path: '/customers/:id',
        builder: (_, state) => CustomerFormScreen(customerId: state.pathParameters['id']),
      ),

      // Founis��
      GoRoute(path: '/suppliers', builder: (_, _) => const SuppliersScreen()),
      GoRoute(path: '/suppliers/new', builder: (_, _) => const SupplierFormScreen()),
      GoRoute(
        path: '/suppliers/:id',
        builder: (_, state) => SupplierFormScreen(supplierId: state.pathParameters['id']),
      ),

      // Acha
      GoRoute(path: '/purchases', builder: (_, _) => const PurchasesScreen()),
      GoRoute(path: '/purchases/new', builder: (_, _) => const PurchaseFormScreen()),

      // Mouvman Stock
      GoRoute(path: '/stock-movements', builder: (_, _) => const StockMovementsScreen()),

      // Sesyon Kès
      GoRoute(path: '/cash-sessions', builder: (_, _) => const CashSessionScreen()),

      // Rapò
      GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),

      // Itilizatè
      GoRoute(path: '/users', builder: (_, _) => const UsersScreen()),
      GoRoute(path: '/users/new', builder: (_, _) => const UserFormScreen()),
      GoRoute(
        path: '/users/:id',
        builder: (_, state) => UserFormScreen(userId: state.pathParameters['id']),
      ),

      // Plan + Renouvèlman
      GoRoute(path: '/plans', builder: (_, _) => const PlansScreen()),

      // APK pèsonalize
      GoRoute(path: '/my-apk', builder: (_, _) => const TenantApkScreen()),

      // System Owner (sèlman)
      GoRoute(path: '/system-owner', builder: (_, _) => const SystemOwnerScreen()),

      // Paramèt
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/settings/business', builder: (_, _) => const BusinessSettingsScreen()),
      GoRoute(path: '/settings/printer', builder: (_, _) => const PrinterSettingsScreen()),
      GoRoute(path: '/settings/profile', builder: (_, _) => const UserFormScreen(selfEdit: true)),
    ],
  );
});

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _sub = _ref.listen(authControllerProvider, (_, _) => notifyListeners());
  }
  final Ref _ref;
  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
