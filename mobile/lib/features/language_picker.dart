import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class LanguageCard extends StatelessWidget {
  const LanguageCard({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<Lang>();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('lang.title'), style: head(16)),
          const SizedBox(height: 4),
          for (final info in kLangs)
            InkWell(
              onTap: () => l.setCode(info.code),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      l.code == info.code ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: l.code == info.code ? Pal.primaryDeep : Pal.outline,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(info.label, style: body(15, w: FontWeight.w600))),
                    if (l.coverage(info.code) < 1)
                      Pill(
                        l.t('lang.coverage', {'n': '${(l.coverage(info.code) * 100).round()}'}),
                        color: Pal.tertiaryDeep,
                        bg: Pal.tertiaryFixed,
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l.t('lang.fallback'), style: body(12, c: Pal.inkSoft)),
          ),
        ],
      ),
    );
  }
}
