// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppL10nFr extends AppL10n {
  AppL10nFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'Petercel';

  @override
  String get home => 'Accueil';

  @override
  String get products => 'Produits';

  @override
  String get sales => 'Ventes';

  @override
  String get newSale => 'Nouvelle Vente';

  @override
  String get history => 'Historique';

  @override
  String get reports => 'Rapports';

  @override
  String get settings => 'Paramètres';

  @override
  String get save => 'Enregistrer';

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get edit => 'Modifier';

  @override
  String get add => 'Ajouter';

  @override
  String get search => 'Rechercher';

  @override
  String get name => 'Nom';

  @override
  String get price => 'Prix';

  @override
  String get stock => 'Stock';

  @override
  String get category => 'Catégorie';

  @override
  String get barcode => 'Code-barres';

  @override
  String get sku => 'SKU';

  @override
  String get subtotal => 'Sous-total';

  @override
  String get discount => 'Remise';

  @override
  String get total => 'Total';

  @override
  String get cart => 'Panier';

  @override
  String get cartEmpty => 'Panier vide';

  @override
  String get checkout => 'Payer';

  @override
  String get paymentMethod => 'Mode de paiement';

  @override
  String get amountReceived => 'Montant Reçu';

  @override
  String get changeDue => 'Monnaie';

  @override
  String get completeSale => 'Confirmer Vente';

  @override
  String get printReceipt => 'Imprimer Reçu';

  @override
  String get businessSetup => 'Configuration Entreprise';

  @override
  String get businessName => 'Nom de l\'entreprise';

  @override
  String get phone => 'Téléphone';

  @override
  String get address => 'Adresse';

  @override
  String get logo => 'Logo';

  @override
  String get currency => 'Devise';

  @override
  String get footerText => 'Texte de bas de page';

  @override
  String get printerSettings => 'Paramètres Imprimante';

  @override
  String get selectPrinter => 'Choisir l\'imprimante';

  @override
  String get connectPrinter => 'Connecter l\'imprimante';

  @override
  String get testPrint => 'Test d\'impression';

  @override
  String get backup => 'Sauvegarde';

  @override
  String get googleDriveBackup => 'Sauvegarde Google Drive';

  @override
  String get signInGoogle => 'Connecter avec Google';

  @override
  String get signOut => 'Déconnecter';

  @override
  String get backupNow => 'Sauvegarder maintenant';

  @override
  String get restoreBackup => 'Restaurer la sauvegarde';

  @override
  String get lastBackup => 'Dernière sauvegarde';

  @override
  String get language => 'Langue';

  @override
  String get today => 'Aujourd\'hui';

  @override
  String get yesterday => 'Hier';

  @override
  String get thisWeek => 'Cette semaine';

  @override
  String get thisMonth => 'Ce mois';

  @override
  String get topProducts => 'Top Produits';

  @override
  String get noProducts => 'Aucun produit';

  @override
  String get noSales => 'Aucune vente';

  @override
  String get thanksForBusiness => 'Merci pour votre achat !';

  @override
  String get receipt => 'Reçu';

  @override
  String saleNumber(int number) {
    return 'Reçu #$number';
  }

  @override
  String get items => 'articles';

  @override
  String get quantity => 'Quantité';

  @override
  String get welcome => 'Bienvenue';
}
