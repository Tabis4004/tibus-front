import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/colis.dart' show GareOption;
import '../../../data/services/accounting_service.dart';
import '../subscription/subscription_notice.dart';
import 'accounting_period.dart';

/// Dépenses de la compagnie (option Comptabilité) : saisie par catégorie
/// OHADA, gare et date — elles alimentent le bilan SYSCOHADA.
class ExpensesScreen extends ConsumerStatefulWidget {
  final String companyId;
  const ExpensesScreen({super.key, required this.companyId});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  AccountingPeriod _period = AccountingPeriod.current(AccountingPeriodKind.month);
  late Future<List<CompanyExpense>> _future = _load();

  Future<List<CompanyExpense>> _load() =>
      ref.read(accountingServiceProvider).listExpenses(widget.companyId, _period.from, _period.to);

  void _reload() => setState(() => _future = _load());

  Future<void> _openForm() async {
    final service = ref.read(accountingServiceProvider);
    List<ExpenseCategory> categories;
    List<GareOption> gares;
    try {
      final results = await Future.wait([
        service.listCategories(widget.companyId),
        ref.read(colisServiceProvider).listGares(widget.companyId),
      ]);
      categories = results[0] as List<ExpenseCategory>;
      gares = results[1] as List<GareOption>;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
      return;
    }
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExpenseForm(companyId: widget.companyId, categories: categories, gares: gares),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(CompanyExpense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette dépense ?'),
        content: Text('${e.categoryName} — ${formatFcfa(e.amount)} FCFA'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(accountingServiceProvider).deleteExpense(widget.companyId, e.id);
      _reload();
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = isAppReadOnly(ref, 'comptabilite');
    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses')),
      floatingActionButton: readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle dépense'),
            ),
      body: Column(
        children: [
          const SubscriptionReadOnlyBanner(appKey: 'comptabilite'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: AccountingPeriodChips(
              period: _period,
              onChanged: (p) => setState(() {
                _period = p;
                _future = _load();
              }),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CompanyExpense>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Erreur : ${snap.error}', textAlign: TextAlign.center),
                    ),
                  );
                }
                final list = snap.data ?? const <CompanyExpense>[];
                final total = list.fold<double>(0, (s, e) => s + e.amount);
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    children: [
                      Text(_period.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('Total : ${formatFcfa(total)} FCFA',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentRed)),
                      const SizedBox(height: 8),
                      if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Aucune dépense sur la période.',
                              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      for (final e in list)
                        Card(
                          child: ListTile(
                            title: Text('${e.ohadaAccountCode} – ${e.categoryName}'),
                            subtitle: Text(
                              '${DateFormat('dd/MM/yyyy').format(e.expenseDate)}'
                              '${e.gareName != null ? " · ${e.gareName}" : ""}'
                              '${(e.description ?? "").isNotEmpty ? "\n${e.description}" : ""}',
                            ),
                            isThreeLine: (e.description ?? '').isNotEmpty,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${formatFcfa(e.amount)} F',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentRed)),
                                if (!readOnly)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20),
                                    onPressed: () => _delete(e),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseForm extends ConsumerStatefulWidget {
  final String companyId;
  final List<ExpenseCategory> categories;
  final List<GareOption> gares;
  const _ExpenseForm({required this.companyId, required this.categories, required this.gares});

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  String? _categoryId;
  String? _gareId;
  DateTime _date = DateTime.now();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.gares.length == 1) _gareId = widget.gares.first.id;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(' ', '').replaceAll(',', '.'));
    if (_categoryId == null || _gareId == null || amount == null || amount <= 0) {
      setState(() => _error = 'Catégorie, gare et montant sont obligatoires.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(accountingServiceProvider).saveExpense(
            companyId: widget.companyId,
            categoryId: _categoryId!,
            amount: amount,
            date: _date,
            description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            gareId: _gareId!,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Échec : $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nouvelle dépense', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Catégorie (compte OHADA) *'),
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.label, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Montant (FCFA) *'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _gareId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Gare *'),
              items: widget.gares.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
              onChanged: (v) => setState(() => _gareId = v),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('Date : ${DateFormat('dd/MM/yyyy').format(_date)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description (facultatif)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
