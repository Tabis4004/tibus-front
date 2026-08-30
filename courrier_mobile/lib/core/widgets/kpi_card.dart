import 'package:flutter/material.dart';

class KpiCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color background;
  final Color foreground;

  const KpiCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.background,
    this.foreground = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: foreground.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: foreground, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(color: foreground, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: foreground.withOpacity(0.9), fontSize: 13),
          ),
        ],
      ),
    );
  }
}