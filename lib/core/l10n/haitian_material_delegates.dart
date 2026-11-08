import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Kreyòl pa nan lis lokalizasyon Material/Cupertino natif yo.
/// Nou redireksyone yo nan franse pou widgets ka jwenn lokalizasyon yo
/// pandan tèks app la rete an Kreyòl.

class HaitianMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const HaitianMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ht';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    return GlobalMaterialLocalizations.delegate.load(const Locale('fr'));
  }

  @override
  bool shouldReload(HaitianMaterialLocalizationsDelegate old) => false;
}

class HaitianCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const HaitianCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ht';

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    return GlobalCupertinoLocalizations.delegate.load(const Locale('fr'));
  }

  @override
  bool shouldReload(HaitianCupertinoLocalizationsDelegate old) => false;
}

class HaitianWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const HaitianWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ht';

  @override
  Future<WidgetsLocalizations> load(Locale locale) {
    return GlobalWidgetsLocalizations.delegate.load(const Locale('fr'));
  }

  @override
  bool shouldReload(HaitianWidgetsLocalizationsDelegate old) => false;
}
