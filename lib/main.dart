import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ulid/ulid.dart';

import 'core/auth/token_store.dart';
import 'core/constants/app_constants.dart';
import 'core/database/app_database.dart';
import 'core/di/providers.dart';
import 'core/l10n/haitian_material_delegates.dart';
import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/sync/hlc.dart';
import 'core/sync/outbox_service.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sqflite has no native binding for Linux/Windows/macOS desktop — use the
  // FFI backend backed by bundled sqlite3.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await initializeDateFormatting('fr_HT');

  // Pare baz done lokal.
  await AppDatabase.instance.database;

  // Pare token store + jenere/retrouve device_id.
  final tokenStore = TokenStore(const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ));
  var deviceId = await tokenStore.deviceId();
  if (deviceId == null) {
    deviceId = Ulid().toCanonical();
    await tokenStore.setDeviceId(deviceId);
  }
  final hlc = Hlc(deviceId: deviceId);

  runApp(ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokenStore),
      hlcProvider.overrideWith((_) async => hlc),
      outboxServiceOverrideProvider.overrideWith(
        (ref) => OutboxService(ref.watch(databaseInstanceProvider), hlc),
      ),
      outboxServiceProvider.overrideWith(
        (ref) => ref.watch(outboxServiceOverrideProvider),
      ),
      syncServiceProvider.overrideWith((ref) {
        final sync = SyncService(
          api: ref.watch(apiClientProvider),
          outbox: ref.watch(outboxServiceOverrideProvider),
          database: ref.watch(databaseInstanceProvider),
          tokenStore: ref.watch(tokenStoreProvider),
        );
        sync.start();
        ref.onDispose(sync.dispose);
        return sync;
      }),
    ],
    child: const WalCashApp(),
  ));
}

class WalCashApp extends ConsumerWidget {
  const WalCashApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    ref.watch(syncServiceProvider); // aktive sync background
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      localizationsDelegates: const [
        HaitianMaterialLocalizationsDelegate(),
        HaitianCupertinoLocalizationsDelegate(),
        HaitianWidgetsLocalizationsDelegate(),
        ...AppL10n.localizationsDelegates,
      ],
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('ht'),
    );
  }
}
