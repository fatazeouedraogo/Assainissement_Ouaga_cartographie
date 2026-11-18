import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/session.dart';
import '../widgets/common.dart';

/// Télécharge la note de décision générée par le serveur et l'ouvre.
class ReportButton extends StatefulWidget {
  const ReportButton({super.key});

  @override
  State<ReportButton> createState() => _ReportButtonState();
}

class _ReportButtonState extends State<ReportButton> {
  bool _busy = false;

  Future<void> _go() async {
    final s = context.read<Session>();
    setState(() => _busy = true);
    try {
      final bytes = await s.api.postBytes('/api/insights/report.pdf', {}, 90);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/note-de-decision-ouagaclean.pdf');
      await f.writeAsBytes(bytes, flush: true);
      final r = await OpenFilex.open(f.path);
      if (mounted && r.type != ResultType.done) {
        toast(context, 'PDF enregistré, mais aucune application pour l’ouvrir.', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) toast(context, 'Impossible d’enregistrer le PDF sur le téléphone.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _go,
      icon: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.picture_as_pdf_outlined),
      label: Text(_busy ? 'Génération du PDF…' : 'Note de décision (PDF)'),
    );
  }
}
