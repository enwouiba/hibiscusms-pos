import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_fr.dart';
import 'app_localizations_ht.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('fr'),
    Locale('ht'),
  ];

  /// No description provided for @appName.
  ///
  /// In ht, this message translates to:
  /// **'Petercel'**
  String get appName;

  /// No description provided for @home.
  ///
  /// In ht, this message translates to:
  /// **'Akèy'**
  String get home;

  /// No description provided for @products.
  ///
  /// In ht, this message translates to:
  /// **'Pwodwi'**
  String get products;

  /// No description provided for @sales.
  ///
  /// In ht, this message translates to:
  /// **'Vant'**
  String get sales;

  /// No description provided for @newSale.
  ///
  /// In ht, this message translates to:
  /// **'Nouvo Vant'**
  String get newSale;

  /// No description provided for @history.
  ///
  /// In ht, this message translates to:
  /// **'Istwa'**
  String get history;

  /// No description provided for @reports.
  ///
  /// In ht, this message translates to:
  /// **'Rapò'**
  String get reports;

  /// No description provided for @settings.
  ///
  /// In ht, this message translates to:
  /// **'Paramèt'**
  String get settings;

  /// No description provided for @save.
  ///
  /// In ht, this message translates to:
  /// **'Anrejistre'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In ht, this message translates to:
  /// **'Anile'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In ht, this message translates to:
  /// **'Efase'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In ht, this message translates to:
  /// **'Modifye'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In ht, this message translates to:
  /// **'Ajoute'**
  String get add;

  /// No description provided for @search.
  ///
  /// In ht, this message translates to:
  /// **'Chèche'**
  String get search;

  /// No description provided for @name.
  ///
  /// In ht, this message translates to:
  /// **'Non'**
  String get name;

  /// No description provided for @price.
  ///
  /// In ht, this message translates to:
  /// **'Pri'**
  String get price;

  /// No description provided for @stock.
  ///
  /// In ht, this message translates to:
  /// **'Stock'**
  String get stock;

  /// No description provided for @category.
  ///
  /// In ht, this message translates to:
  /// **'Kategori'**
  String get category;

  /// No description provided for @barcode.
  ///
  /// In ht, this message translates to:
  /// **'Kòd ba'**
  String get barcode;

  /// No description provided for @sku.
  ///
  /// In ht, this message translates to:
  /// **'SKU'**
  String get sku;

  /// No description provided for @subtotal.
  ///
  /// In ht, this message translates to:
  /// **'Soustotal'**
  String get subtotal;

  /// No description provided for @discount.
  ///
  /// In ht, this message translates to:
  /// **'Rabè'**
  String get discount;

  /// No description provided for @total.
  ///
  /// In ht, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @cart.
  ///
  /// In ht, this message translates to:
  /// **'Panye'**
  String get cart;

  /// No description provided for @cartEmpty.
  ///
  /// In ht, this message translates to:
  /// **'Panye a vid'**
  String get cartEmpty;

  /// No description provided for @checkout.
  ///
  /// In ht, this message translates to:
  /// **'Peye'**
  String get checkout;

  /// No description provided for @paymentMethod.
  ///
  /// In ht, this message translates to:
  /// **'Mwayen Peman'**
  String get paymentMethod;

  /// No description provided for @amountReceived.
  ///
  /// In ht, this message translates to:
  /// **'Lajan Resi'**
  String get amountReceived;

  /// No description provided for @changeDue.
  ///
  /// In ht, this message translates to:
  /// **'Monnen'**
  String get changeDue;

  /// No description provided for @completeSale.
  ///
  /// In ht, this message translates to:
  /// **'Konfime Vant'**
  String get completeSale;

  /// No description provided for @printReceipt.
  ///
  /// In ht, this message translates to:
  /// **'Enprime Resi'**
  String get printReceipt;

  /// No description provided for @businessSetup.
  ///
  /// In ht, this message translates to:
  /// **'Konfigirasyon Biznis'**
  String get businessSetup;

  /// No description provided for @businessName.
  ///
  /// In ht, this message translates to:
  /// **'Non Biznis'**
  String get businessName;

  /// No description provided for @phone.
  ///
  /// In ht, this message translates to:
  /// **'Telefòn'**
  String get phone;

  /// No description provided for @address.
  ///
  /// In ht, this message translates to:
  /// **'Adrès'**
  String get address;

  /// No description provided for @logo.
  ///
  /// In ht, this message translates to:
  /// **'Logo'**
  String get logo;

  /// No description provided for @currency.
  ///
  /// In ht, this message translates to:
  /// **'Lajan'**
  String get currency;

  /// No description provided for @footerText.
  ///
  /// In ht, this message translates to:
  /// **'Tèks Pye Paj'**
  String get footerText;

  /// No description provided for @printerSettings.
  ///
  /// In ht, this message translates to:
  /// **'Paramèt Printer'**
  String get printerSettings;

  /// No description provided for @selectPrinter.
  ///
  /// In ht, this message translates to:
  /// **'Chwazi Printer'**
  String get selectPrinter;

  /// No description provided for @connectPrinter.
  ///
  /// In ht, this message translates to:
  /// **'Konekte Printer'**
  String get connectPrinter;

  /// No description provided for @testPrint.
  ///
  /// In ht, this message translates to:
  /// **'Teste Enprime'**
  String get testPrint;

  /// No description provided for @backup.
  ///
  /// In ht, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @googleDriveBackup.
  ///
  /// In ht, this message translates to:
  /// **'Backup Google Drive'**
  String get googleDriveBackup;

  /// No description provided for @signInGoogle.
  ///
  /// In ht, this message translates to:
  /// **'Konekte ak Google'**
  String get signInGoogle;

  /// No description provided for @signOut.
  ///
  /// In ht, this message translates to:
  /// **'Dekonekte'**
  String get signOut;

  /// No description provided for @backupNow.
  ///
  /// In ht, this message translates to:
  /// **'Backup Kounye a'**
  String get backupNow;

  /// No description provided for @restoreBackup.
  ///
  /// In ht, this message translates to:
  /// **'Retabli Backup'**
  String get restoreBackup;

  /// No description provided for @lastBackup.
  ///
  /// In ht, this message translates to:
  /// **'Dènye Backup'**
  String get lastBackup;

  /// No description provided for @language.
  ///
  /// In ht, this message translates to:
  /// **'Lang'**
  String get language;

  /// No description provided for @today.
  ///
  /// In ht, this message translates to:
  /// **'Jodi a'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In ht, this message translates to:
  /// **'Yè'**
  String get yesterday;

  /// No description provided for @thisWeek.
  ///
  /// In ht, this message translates to:
  /// **'Semèn sa'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In ht, this message translates to:
  /// **'Mwa sa'**
  String get thisMonth;

  /// No description provided for @topProducts.
  ///
  /// In ht, this message translates to:
  /// **'Pi Bon Pwodwi'**
  String get topProducts;

  /// No description provided for @noProducts.
  ///
  /// In ht, this message translates to:
  /// **'Pa gen pwodwi'**
  String get noProducts;

  /// No description provided for @noSales.
  ///
  /// In ht, this message translates to:
  /// **'Pa gen vant'**
  String get noSales;

  /// No description provided for @thanksForBusiness.
  ///
  /// In ht, this message translates to:
  /// **'Mèsi paske w achte lakay nou!'**
  String get thanksForBusiness;

  /// No description provided for @receipt.
  ///
  /// In ht, this message translates to:
  /// **'Resi'**
  String get receipt;

  /// No description provided for @saleNumber.
  ///
  /// In ht, this message translates to:
  /// **'Resi #{number}'**
  String saleNumber(int number);

  /// No description provided for @items.
  ///
  /// In ht, this message translates to:
  /// **'atik'**
  String get items;

  /// No description provided for @quantity.
  ///
  /// In ht, this message translates to:
  /// **'Kantite'**
  String get quantity;

  /// No description provided for @welcome.
  ///
  /// In ht, this message translates to:
  /// **'Byenveni'**
  String get welcome;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['fr', 'ht'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'fr':
      return AppL10nFr();
    case 'ht':
      return AppL10nHt();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
