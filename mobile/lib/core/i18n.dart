import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LangInfo {
  const LangInfo(this.code, this.label);
  final String code;
  final String label;
}

const kLangs = [
  LangInfo('fr', 'Français'),
  LangInfo('en', 'English'),
  LangInfo('mos', 'Mooré'),
  LangInfo('dyu', 'Dioula'),
];

/// Textes de l'application, lus dans assets/i18n/<code>.json.
/// Une clé absente ou vide dans une langue retombe sur le français.
class Lang extends ChangeNotifier {
  Lang._(this._prefs, this.code, this._maps);

  final SharedPreferences _prefs;
  final Map<String, Map<String, String>> _maps;
  String code;

  static Future<Map<String, String>> _read(String c) async {
    try {
      final raw = await rootBundle.loadString('assets/i18n/$c.json');
      return {
        for (final e in (jsonDecode(raw) as Map).entries) e.key.toString(): '${e.value}',
      };
    } catch (_) {
      return {};
    }
  }

  static Future<Lang> load() async {
    final p = await SharedPreferences.getInstance();
    final maps = {for (final l in kLangs) l.code: await _read(l.code)};
    final saved = p.getString('lang');
    final code = kLangs.any((l) => l.code == saved) ? saved! : 'fr';
    return Lang._(p, code, maps);
  }

  String t(String key, [Map<String, String>? args]) {
    final v = _maps[code]?[key];
    var s = (v != null && v.trim().isNotEmpty) ? v : (_maps['fr']?[key] ?? key);
    args?.forEach((k, val) => s = s.replaceAll('{$k}', val));
    return s;
  }

  /// Part des textes réellement traduits dans une langue (0 à 1).
  double coverage(String c) {
    final fr = _maps['fr'] ?? {};
    if (fr.isEmpty) return 0;
    final m = _maps[c] ?? {};
    return fr.keys.where((k) => (m[k] ?? '').trim().isNotEmpty).length / fr.length;
  }

  Future<void> setCode(String c) async {
    code = c;
    await _prefs.setString('lang', c);
    notifyListeners();
  }
}

extension TrX on BuildContext {
  /// À utiliser dans build() : l'écran se met à jour au changement de langue.
  String tr(String key, [Map<String, String>? args]) => watch<Lang>().t(key, args);

  /// À utiliser dans un gestionnaire d'événement ou après un await.
  String trRead(String key, [Map<String, String>? args]) => read<Lang>().t(key, args);
}
