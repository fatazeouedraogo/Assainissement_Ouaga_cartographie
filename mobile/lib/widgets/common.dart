import 'package:flutter/material.dart';

import '../core/theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Pal.line),
          ),
          child: child,
        ),
      ),
    );
  }
}

class Kpi extends StatelessWidget {
  const Kpi(this.value, this.label, {super.key, this.color = Pal.ink, this.icon});
  final String value;
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) Icon(icon, size: 18, color: color),
          if (icon != null) const SizedBox(height: 6),
          Text(value, style: head(26, c: color)),
          const SizedBox(height: 2),
          Text(label, style: body(12, c: Pal.inkSoft, h: 1.25)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(text, style: head(17))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Pal.onPrimaryFixed, this.bg = Pal.primaryFixed});
  final String text;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(
        text,
        style: body(11, w: FontWeight.w700, c: color),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.title, [this.text]);
  final IconData icon;
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: Pal.primaryFixed, shape: BoxShape.circle),
              child: Icon(icon, color: Pal.primaryDeep, size: 30),
            ),
            const SizedBox(height: 16),
            Text(title, style: head(17), textAlign: TextAlign.center),
            if (text != null) ...[
              const SizedBox(height: 6),
              Text(
                text!,
                style: body(13, c: Pal.inkSoft, h: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState(this.message, this.onRetry, {super.key});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: Pal.outline),
            const SizedBox(height: 12),
            Text(
              message,
              style: body(14, c: Pal.inkSoft, h: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 180,
              child: OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
            ),
          ],
        ),
      ),
    );
  }
}

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? Pal.error : Pal.ink));
}

Future<T?> pickOption<T>(BuildContext context, String title, Map<T, String> options) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: head(18)),
            const SizedBox(height: 8),
            for (final e in options.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.value, style: body(15, w: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right, color: Pal.outline),
                onTap: () => Navigator.pop(c, e.key),
              ),
          ],
        ),
      ),
    ),
  );
}
