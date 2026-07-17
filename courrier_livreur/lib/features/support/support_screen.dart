import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/ticket.dart';
import '../../data/services/driver_backend.dart';
import 'ticket_thread_screen.dart';

/// Support / tickets — portage de support.tsx côté tibusride-front. Le
/// livreur est déjà authentifié directement (pas de compte miroir ici,
/// contrairement à courrier_client) donc pas de verrou de connexion : cet
/// écran n'est de toute façon accessible que depuis le profil, déjà
/// protégé.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<SupportTicket>? _tickets;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _tickets = null;
      _error = null;
    });
    try {
      final tickets = await DriverBackend.listMyTickets();
      if (mounted) setState(() => _tickets = tickets);
    } catch (e) {
      if (mounted) {
        setState(() {
          _tickets = const [];
          _error = 'Chargement impossible : $e';
        });
      }
    }
  }

  Future<void> _openNewTicket() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewTicketSheet(),
    );
    if (created == true) _load();
  }

  Color _statusColor(String status) => switch (status) {
        'resolved' => AppColors.primaryGreenDark,
        'closed' => AppColors.textSecondary,
        'pending' => AppColors.accentOrange,
        _ => Colors.blue,
      };

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} à ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final tickets = _tickets;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Support')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewTicket,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau ticket'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: tickets == null
            ? const Center(child: CircularProgressIndicator())
            : tickets.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Icon(Icons.support_agent_outlined, size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          _error ?? 'Aucun ticket pour l\'instant.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    itemCount: tickets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final t = tickets[index];
                      return Container(
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          title: Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(
                            '${ticketCategoryLabel[t.category] ?? t.category} · ${_formatDate(t.lastMessageAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(t.statusLabel, style: const TextStyle(fontSize: 11, color: Colors.white)),
                            backgroundColor: _statusColor(t.status),
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => TicketThreadScreen(ticketId: t.id, backend: _DriverTicketBackend())),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _NewTicketSheet extends StatefulWidget {
  const _NewTicketSheet();

  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _category = 'other';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (subject.length < 3 || body.length < 5) {
      setState(() => _error = 'Sujet (min. 3 caractères) et message (min. 5 caractères) requis.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await DriverBackend.createTicket(subject: subject, category: _category, body: body);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nouveau ticket', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(controller: _subjectCtrl, decoration: const InputDecoration(labelText: 'Sujet')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Catégorie'),
            items: ticketCategoryLabel.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _category = v ?? 'other'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            decoration: const InputDecoration(labelText: 'Décrivez votre problème'),
            maxLines: 4,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Envoyer'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Implémentation de [TicketBackend] adossée à DriverBackend, injectée dans
/// l'écran de fil partagé — voir ticket_thread_screen.dart.
class _DriverTicketBackend implements TicketBackend {
  @override
  String? get currentUserId => DriverBackend.currentUser?.id;
  @override
  Future<SupportTicket> getTicket(String ticketId) => DriverBackend.getTicket(ticketId);
  @override
  Future<List<TicketMessage>> listMessages(String ticketId) => DriverBackend.listTicketMessages(ticketId);
  @override
  Future<void> sendMessage(String ticketId, String body) => DriverBackend.sendTicketMessage(ticketId, body);
  @override
  Future<void> closeTicket(String ticketId) => DriverBackend.closeTicket(ticketId);
}
