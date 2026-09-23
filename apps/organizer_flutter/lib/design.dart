import 'package:flutter/material.dart';

abstract final class SendohColors {
  static const teal = Color(0xFF0B3D3B),
      tealSoft = Color(0xFFE1EEEC),
      orange = Color(0xFFE8A33D);
  static const canvas = Color(0xFFFBF9F6),
      surface = Colors.white,
      border = Color(0xFFE1DFD9);
  static const ink = Color(0xFF15221F),
      secondary = Color(0xFF4A5754),
      muted = Color(0xFF657069);
  static const green = Color(0xFF1E7A46),
      amber = Color(0xFF97690A),
      amberSoft = Color(0xFFFDF3DA),
      red = Color(0xFFB3261E),
      blue = Color(0xFF2A5DB0);
}

ThemeData sendohTheme() {
  final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: SendohColors.canvas,
      colorScheme: ColorScheme.fromSeed(
          seedColor: SendohColors.teal,
          primary: SendohColors.teal,
          surface: SendohColors.canvas,
          error: SendohColors.red));
  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: SendohColors.ink, displayColor: SendohColors.ink),
    appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: SendohColors.canvas,
        foregroundColor: SendohColors.ink,
        titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: SendohColors.ink)),
    dividerTheme: const DividerThemeData(
        color: SendohColors.border, thickness: .6, space: 28),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SendohColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        labelStyle:
            const TextStyle(fontSize: 14, color: SendohColors.secondary),
        hintStyle: const TextStyle(fontSize: 14, color: SendohColors.muted),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: SendohColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: const BorderSide(color: SendohColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide:
                const BorderSide(color: SendohColors.teal, width: 1.5))),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 49),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 49),
            side: const BorderSide(color: SendohColors.border),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
    navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SendohColors.surface,
        indicatorColor: SendohColors.tealSoft,
        labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, color: SendohColors.teal))),
  );
}

class SendohMark extends StatelessWidget {
  const SendohMark({super.key, this.size = 38});
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * 2 / 3, size), painter: _MarkPainter());
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40, size.height / 60);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = SendohColors.teal;
    canvas.drawPath(
        Path()
          ..moveTo(29, 15)
          ..lineTo(25, 10)
          ..cubicTo(17, 1, 3, 8, 5, 19)
          ..cubicTo(6, 24, 12, 29, 20, 37),
        paint);
    paint.color = SendohColors.orange;
    canvas.drawPath(
        Path()
          ..moveTo(11, 45)
          ..lineTo(15, 50)
          ..cubicTo(23, 59, 37, 52, 35, 41)
          ..cubicTo(34, 36, 28, 31, 20, 23),
        paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SendohBrand extends StatelessWidget {
  const SendohBrand({super.key, this.vertical = false});
  final bool vertical;
  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[
      SendohMark(size: vertical ? 54 : 32),
      SizedBox(width: vertical ? 0 : 8, height: vertical ? 12 : 0),
      Text('SENDOH',
          style: TextStyle(
              fontSize: vertical ? 30 : 23,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
              color: SendohColors.teal))
    ];
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: parts)
        : Row(mainAxisSize: MainAxisSize.min, children: parts);
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(18),
      this.color = SendohColors.surface});
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SendohColors.border, width: .7)),
      child: child);
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar(this.name, {super.key, this.radius = 19});
  final String name;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
      radius: radius,
      backgroundColor: SendohColors.tealSoft,
      child: Text(
          name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
          style: TextStyle(
              fontSize: radius * .8,
              fontWeight: FontWeight.w600,
              color: SendohColors.teal)));
}

class CollectionSymbol extends StatelessWidget {
  const CollectionSymbol({super.key});
  @override
  Widget build(BuildContext context) => const CircleAvatar(
      backgroundColor: SendohColors.tealSoft,
      radius: 20,
      child: Icon(Icons.groups_outlined, color: SendohColors.teal, size: 23));
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, this.pending = false});
  final String text;
  final bool pending;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
          color: pending ? SendohColors.amberSoft : SendohColors.tealSoft,
          borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: pending ? SendohColors.amber : SendohColors.teal)));
}

class SummaryRow extends StatelessWidget {
  const SummaryRow(this.label, this.value, {super.key, this.bold = false});
  final String label, value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: SendohColors.secondary,
                    fontWeight: bold ? FontWeight.w600 : null))),
        const SizedBox(width: 16),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13,
                    color: bold ? SendohColors.teal : SendohColors.ink,
                    fontWeight: FontWeight.w600)))
      ]));
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.title,
      required this.message,
      this.icon = Icons.groups_outlined});
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Column(children: [
        CircleAvatar(
            radius: 28,
            backgroundColor: SendohColors.tealSoft,
            child: Icon(icon, color: SendohColors.teal, size: 28)),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, height: 1.6, color: SendohColors.secondary))
      ]));
}

String displayDate(dynamic raw) {
  if (raw == null) return 'No deadline';
  final date = DateTime.tryParse(raw.toString());
  if (date == null) return 'No deadline';
  final d = date.toUtc().add(const Duration(hours: 1));
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
