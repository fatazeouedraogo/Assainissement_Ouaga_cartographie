import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const languages = {'fr': 'Français', 'en': 'English', 'mos': 'Mooré', 'dyu': 'Dioula'};

class I18n {
  static String lang = 'fr';
  static final Map<String, Map<String, String>> _tables = {};

  static Future<void> load() async {
    for (final code in languages.keys) {
      try {
        final raw = jsonDecode(await rootBundle.loadString('assets/i18n/$code.json')) as Map<String, dynamic>;
        _tables[code] = raw.map((k, v) => MapEntry(k, '$v'));
      } catch (_) {
        _tables[code] = {};
      }
    }
    final p = await SharedPreferences.getInstance();
    lang = p.getString('lang') ?? 'fr';
  }

  static Future<void> set(String code) async {
    lang = code;
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', code);
  }

  static String t(String key) {
    final v = _tables[lang]?[key];
    if (v != null && v.isNotEmpty) return v;
    return _tables['fr']?[key] ?? key;
  }
}

String tr(String key) => I18n.t(key);
