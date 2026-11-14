class AppConstants {
  AppConstants._();

  // App identity yo mete via --dart-define lè build pèsonalize.
  // Defo: WalCash POS (jenerik).
  static const String appName = String.fromEnvironment('APP_NAME', defaultValue: 'WalCash POS');
  static const String appTagline = String.fromEnvironment('APP_TAGLINE', defaultValue: 'POS');
  static const String dbName = 'walcash_pos.db';
  static const int dbVersion = 10;

  static const String defaultCurrency = 'USD';
  static const String defaultLocale = 'ht';

  static String get backupFolderName => '$appName Backups';
  static const String backupFilePrefix = 'walcash_backup_';

  static const int receiptWidth58mm = 384;
  static const int receiptWidth80mm = 576;

  // ---------- Antèt resi (enfo biznis) ----------
  // Defo = HIBISCUS MULTI-SERVICES (ka chanje via --dart-define pou lòt build).
  static const String receiptBusinessName =
      String.fromEnvironment('RECEIPT_NAME', defaultValue: 'HIBISCUS MULTI-SERVICES');
  static const String receiptBusinessAddress =
      String.fromEnvironment('RECEIPT_ADDRESS', defaultValue: 'Fond des Blancs - Sud Haiti');
  static const String receiptBusinessNif =
      String.fromEnvironment('RECEIPT_NIF', defaultValue: '000-666-762-9');
  static const String receiptBusinessPhone =
      String.fromEnvironment('RECEIPT_PHONE', defaultValue: '364 627 63 / 4118 81 81');
  static const String receiptBusinessEmail =
      String.fromEnvironment('RECEIPT_EMAIL', defaultValue: 'hibiscusmultiservice@gmail.com');

  // ---------- Sync ----------
  /// URL backend Laravel. Chanje pou domèn pwòp ou pita.
  /// Egzanp: https://api.kinkayri.com
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',  // emulator → host localhost
  );

  /// Entèval push (sekonn) — fò pou voye chanjman lokal pi vit
  static const int syncPushIntervalSeconds = 15;

  /// Entèval pull (sekonn)
  static const int syncPullIntervalSeconds = 15;

  /// Max operasyon pa batch push
  static const int syncBatchSize = 200;

  // ---------- Google Drive (eritye) ----------
  static const String googleWebClientId =
      '520631597762-5me9ovhate41v6ekgv58l170637sefno.apps.googleusercontent.com';
}
