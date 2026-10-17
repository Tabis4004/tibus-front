import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Période d'un écran comptable : mois, trimestre, année en cours ou dates
/// choisies (même choix que le bilan Gestabis).
enum AccountingPeriodKind { month, quarter, year, custom }

class AccountingPeriod {
  final AccountingPeriodKind kind;
  final DateTime from;
  final DateTime to;
  const AccountingPeriod(this.kind, this.from, this.to);

  static AccountingPeriod current(AccountingPeriodKind kind) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (kind) {
      case AccountingPeriodKind.month:
        return AccountingPeriod(kind, DateTime(now.year, now.month, 1), today);
      case AccountingPeriodKind.quarter:
        final firstMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return AccountingPeriod(kind, DateTime(now.year, firstMonth, 1), today);
      case AccountingPeriodKind.year:
      case AccountingPeriodKind.custom:
        return AccountingPeriod(kind, DateTime(now.year, 1, 1), today);
    }
  }

  String get label {
    final f = DateFormat('dd/MM/yyyy');
    return 'Du ${f.format(from)} au ${f.format(to)}';
  }
}

String formatFcfa(num value) {
  final s = NumberFormat.decimalPattern('fr').format(value.round()).replaceAll(' ', ' ').replaceAll(' ', ' ');
  return s;
}

/// Puces de choix de période.
class AccountingPeriodChips extends StatelessWidget {
  final AccountingPeriod period;
  final ValueChanged<AccountingPeriod> onChanged;
  const AccountingPeriodChips({super.key, required this.period, required this.onChanged});

  Future<void> _pickCustom(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: period.from, end: period.to),
    );
    if (range != null) {
      onChanged(AccountingPeriod(AccountingPeriodKind.custom, range.start, range.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, AccountingPeriodKind kind) => ChoiceChip(
          label: Text(label),
          selected: period.kind == kind,
          onSelected: (_) => kind == AccountingPeriodKind.custom
              ? _pickCustom(context)
              : onChanged(AccountingPeriod.current(kind)),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        chip('Mois en cours', AccountingPeriodKind.month),
        chip('Trimestre en cours', AccountingPeriodKind.quarter),
        chip('Année en cours', AccountingPeriodKind.year),
        chip('Personnalisé', AccountingPeriodKind.custom),
      ],
    );
  }
}
