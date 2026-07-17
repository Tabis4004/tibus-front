import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/ticket.dart';

/// Petite interface d'abstraction pour que cet écran de fil de messages soit
/// utilisable tel quel indépendamment du backend concret (ici RideBackend) —
/// évite un couplage direct qui rendrait le fichier moins facile à relire
/// isolément.
abstract class TicketBackend {
  String? get currentUserId;
  Future<SupportTicket> getTicket(String ticketId);
  Future<List<TicketMessage>> listMessages(String ticketId);
  Future<void> sendMessage(String ticketId, String body);
  Future<void> closeTicket(String ticketId);
}

/// Fil de discussion d'un ticket — portage de ticket.$ticketId.tsx, version
/// "propriétaire" uniquement (pas de vue agent : statut/priorité/assignation
/// ne sont pas modifiables ici, les notes internes ne sont de toute façon
/// jamais renvoyées par RLS à un non-agent). Polling léger (10s) tant que
/// l'écran est ouvert, comme le comportement web (pas de realtime).
class TicketThreadScreen extends StatefulWidget {
  final String ticketId;
  final TicketBackend backend;
  const TicketThreadScreen({super.key, required this.ticketId, required this.backend});

  @override
  State<TicketThreadScreen> createState() => _TicketThreadScreenState();
}

class _TicketThreadScreenState extends State<TicketThreadScreen> {
  SupportTicket? _ticket;
  List<TicketMessage> _messages = [];
  bool _loading = true;
  String? _error;
  Timer? _poll;
  final _bodyCtrl = TextEditingController();
  bool _sending = false;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _bodyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.backend.getTicket(widget.ticketId),
        widget.backend.listMessages(widget.ticketId),
      ]);
      if (!mounted) return;
      setState(() {
        _ticket = results[0] as SupportTicket;
        _messages = results[1] as List<TicketMessage>;
        _error = null;
      });
    } catch (e) {
      if (mounted && !silent) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.backend.sendMessage(widget.ticketId, body);
      _bodyCtrl.clear();
      await _load(silent: true);
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fermer ce ticket ?'),
        content: const Text('Vous ne pourrez plus y répondre une fois fermé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fermer le ticket')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.backend.closeTicket(widget.ticketId);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    final myId = widget.backend.currentUserId;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(ticket?.subject ?? 'Ticket', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (ticket != null && !ticket.isClosed)
            IconButton(onPressed: _close, icon: const Icon(Icons.check_circle_outline), tooltip: 'Fermer le ticket'),
        ],
      ),
      body: _loading && ticket == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (ticket != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: AppColors.primaryGreenLight,
                    child: Text(
                      '${ticketCategoryLabel[ticket.category] ?? ticket.category} · ${ticket.statusLabel}',
                      style: const TextStyle(fontSize: 12, color: AppColors.primaryGreenDark, fontWeight: FontWeight.w600),
                    ),
                  ),
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(child: Text('Aucun message.', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final m = _messages[index];
                            final mine = m.authorId == myId;
                            return Align(
                              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(10),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                decoration: BoxDecoration(
                                  color: mine ? AppColors.primaryGreenDark : AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: mine ? null : Border.all(color: AppColors.divider),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.body, style: TextStyle(color: mine ? Colors.white : AppColors.textPrimary, fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTime(m.createdAt),
                                      style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (_error != null)
                  Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12))),
                if (ticket != null && ticket.isClosed)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Ce ticket est fermé.', style: TextStyle(color: AppColors.textSecondary)),
                  )
                else
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _bodyCtrl,
                              decoration: const InputDecoration(hintText: 'Votre message…', isDense: true),
                              minLines: 1,
                              maxLines: 4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _sending ? null : _send,
                            icon: _sending
                                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send, color: AppColors.primaryGreenDark),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
