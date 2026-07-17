import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

String _formatXof(num amount) {
  final s = amount.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${amount < 0 ? '-' : ''}$buf FCFA';
}

/// Facturation — portage de BillingTab (admin.tsx) : comptes corporate +
/// factures (création avec lignes dynamiques, TVA 18% auto-calculée,
/// changement de statut, enregistrement de paiements). RLS gère déjà le
/// cantonnement pays d'un admin non-superadmin (voir DriverBackend).
class BillingAdminScreen extends StatefulWidget {
  const BillingAdminScreen({super.key});

  @override
  State<BillingAdminScreen> createState() => _BillingAdminScreenState();
}

class _BillingAdminScreenState extends State<BillingAdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturation'),
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'Entités'), Tab(text: 'Factures')]),
      ),
      body: TabBarView(controller: _tab, children: const [_CorporatesTab(), _InvoicesTab()]),
    );
  }
}

class _CorporatesTab extends StatefulWidget {
  const _CorporatesTab();
  @override
  State<_CorporatesTab> createState() => _CorporatesTabState();
}

class _CorporatesTabState extends State<_CorporatesTab> {
  List<Map<String, dynamic>> _corporates = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DriverBackend.fetchCorporates();
      if (mounted) setState(() => _corporates = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final taxCtrl = TextEditingController();
    String country = DriverBackend.serviceCountries.first;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nouvelle entité corporate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom')),
              const SizedBox(height: 8),
              TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: 'Contact')),
              const SizedBox(height: 8),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Téléphone')),
              const SizedBox(height: 8),
              TextField(controller: taxCtrl, decoration: const InputDecoration(labelText: 'N° fiscal')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: country,
                decoration: const InputDecoration(labelText: 'Pays'),
                items: DriverBackend.serviceCountries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => country = v ?? country),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Créer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await DriverBackend.createCorporate({
        'name': nameCtrl.text.trim(),
        if (contactCtrl.text.trim().isNotEmpty) 'contact_name': contactCtrl.text.trim(),
        if (emailCtrl.text.trim().isNotEmpty) 'email': emailCtrl.text.trim(),
        if (phoneCtrl.text.trim().isNotEmpty) 'phone': phoneCtrl.text.trim(),
        if (taxCtrl.text.trim().isNotEmpty) 'tax_id': taxCtrl.text.trim(),
        'country': country,
        'active': true,
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Entité')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)))])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    itemCount: _corporates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final c = _corporates[i];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            Text('${c['contact_name'] ?? ''} · ${c['email'] ?? ''} · ${c['country'] ?? ''}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _InvoicesTab extends StatefulWidget {
  const _InvoicesTab();
  @override
  State<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends State<_InvoicesTab> {
  List<Map<String, dynamic>> _invoices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DriverBackend.fetchInvoices();
      if (mounted) setState(() => _invoices = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createInvoice() async {
    final corporates = await DriverBackend.fetchCorporates();
    if (corporates.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créez d\'abord une entité corporate.')));
      return;
    }
    if (!mounted) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewInvoiceSheet(corporates: corporates),
    );
    if (created == true) _load();
  }

  Future<void> _changeStatus(String invoiceId, String status) async {
    try {
      await DriverBackend.updateInvoiceStatus(invoiceId, status);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _openPayment(Map<String, dynamic> invoice) async {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => _PaymentSheet(invoice: invoice));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _createInvoice, icon: const Icon(Icons.add), label: const Text('Facture')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)))])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    itemCount: _invoices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final inv = _invoices[i];
                      final corporate = inv['corporate'] as Map<String, dynamic>?;
                      final status = inv['status'] as String? ?? 'draft';
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text('${inv['number'] ?? 'Brouillon'} — ${corporate?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ),
                              Text(_formatXof((inv['total_xof'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ]),
                            Text('Payé : ${_formatXof((inv['paid_xof'] as num?) ?? 0)}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: status,
                                    decoration: const InputDecoration(isDense: true, labelText: 'Statut'),
                                    items: DriverBackend.invoiceStatusLabel.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                                    onChanged: (v) {
                                      if (v != null) _changeStatus(inv['id'] as String, v);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(onPressed: () => _openPayment(inv), child: const Text('Paiement')),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _NewInvoiceSheet extends StatefulWidget {
  final List<Map<String, dynamic>> corporates;
  const _NewInvoiceSheet({required this.corporates});

  @override
  State<_NewInvoiceSheet> createState() => _NewInvoiceSheetState();
}

class _ItemDraft {
  final descCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final priceCtrl = TextEditingController();
}

class _NewInvoiceSheetState extends State<_NewInvoiceSheet> {
  String? _corporateId;
  final _notesCtrl = TextEditingController();
  final List<_ItemDraft> _items = [_ItemDraft()];
  bool _submitting = false;
  String? _error;

  int get _subtotal => _items.fold(0, (s, it) {
        final q = double.tryParse(it.qtyCtrl.text) ?? 0;
        final p = int.tryParse(it.priceCtrl.text) ?? 0;
        return s + (q * p).round();
      });
  int get _vat => (_subtotal * 0.18).round();
  int get _total => _subtotal + _vat;

  Future<void> _submit() async {
    if (_corporateId == null) {
      setState(() => _error = 'Choisissez une entité.');
      return;
    }
    final items = _items
        .where((it) => it.descCtrl.text.trim().isNotEmpty)
        .map((it) => {
              'description': it.descCtrl.text.trim(),
              'quantity': double.tryParse(it.qtyCtrl.text) ?? 1,
              'unit_price_xof': int.tryParse(it.priceCtrl.text) ?? 0,
            })
        .toList();
    if (items.isEmpty) {
      setState(() => _error = 'Ajoutez au moins une ligne.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await DriverBackend.createInvoice(corporateId: _corporateId!, notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(), items: items);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nouvelle facture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _corporateId,
              decoration: const InputDecoration(labelText: 'Entité'),
              items: widget.corporates.map((c) => DropdownMenuItem(value: c['id'] as String, child: Text(c['name'] as String? ?? ''))).toList(),
              onChanged: (v) => setState(() => _corporateId = v),
            ),
            const SizedBox(height: 12),
            const Text('Lignes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ..._items.map((it) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: TextField(controller: it.descCtrl, decoration: const InputDecoration(labelText: 'Description', isDense: true))),
                      const SizedBox(width: 6),
                      Expanded(child: TextField(controller: it.qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qté', isDense: true), onChanged: (_) => setState(() {}))),
                      const SizedBox(width: 6),
                      Expanded(child: TextField(controller: it.priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PU FCFA', isDense: true), onChanged: (_) => setState(() {}))),
                    ],
                  ),
                )),
            TextButton.icon(onPressed: () => setState(() => _items.add(_ItemDraft())), icon: const Icon(Icons.add, size: 16), label: const Text('Ajouter une ligne')),
            const Divider(),
            Text('Sous-total : ${_formatXof(_subtotal)}', style: const TextStyle(fontSize: 12)),
            Text('TVA (18%) : ${_formatXof(_vat)}', style: const TextStyle(fontSize: 12)),
            Text('Total : ${_formatXof(_total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Notes (optionnel)'), maxLines: 2),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Créer la facture'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentSheet extends StatefulWidget {
  final Map<String, dynamic> invoice;
  const _PaymentSheet({required this.invoice});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  String _method = 'mobile_money';
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await DriverBackend.fetchInvoicePayments(widget.invoice['id'] as String);
      if (mounted) setState(() => _history = rows);
    } catch (_) {
      // best-effort
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Montant invalide.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await DriverBackend.recordInvoicePayment(invoiceId: widget.invoice['id'] as String, amountXof: amount, method: _method, reference: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paiement — ${widget.invoice['number'] ?? 'facture'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant (FCFA)')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _method,
              decoration: const InputDecoration(labelText: 'Méthode'),
              items: DriverBackend.paymentMethodLabel.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
            const SizedBox(height: 8),
            TextField(controller: _refCtrl, decoration: const InputDecoration(labelText: 'Référence (optionnel)')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Enregistrer'),
              ),
            ),
            const Divider(height: 24),
            const Text('Historique', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            if (_loadingHistory)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator()))
            else if (_history.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Aucun paiement enregistré.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)))
            else
              ..._history.map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${p['paid_on'] ?? ''} · ${DriverBackend.paymentMethodLabel[p['method']] ?? p['method']}', style: const TextStyle(fontSize: 11)),
                        Text(_formatXof((p['amount_xof'] as num?) ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
