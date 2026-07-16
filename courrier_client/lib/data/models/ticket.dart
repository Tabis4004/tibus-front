/// Support / tickets — portage de `support_tickets`/`ticket_messages` côté
/// tibusride-front (support.tsx, ticket.$ticketId.tsx). Table unique
/// partagée entre passagers, livreurs et agents (RLS filtrée sur
/// created_by), pas de pièces jointes, pas de realtime (polling côté web,
/// on reproduit avec un pull-to-refresh + polling léger).
class SupportTicket {
  final String id;
  final String subject;
  final String category;
  final String priority;
  final String status;
  final DateTime lastMessageAt;
  final DateTime? closedAt;
  final DateTime createdAt;

  const SupportTicket({
    required this.id,
    required this.subject,
    required this.category,
    required this.priority,
    required this.status,
    required this.lastMessageAt,
    this.closedAt,
    required this.createdAt,
  });

  factory SupportTicket.fromMap(Map<String, dynamic> map) => SupportTicket(
        id: map['id'] as String,
        subject: map['subject'] as String? ?? '',
        category: map['category'] as String? ?? 'other',
        priority: map['priority'] as String? ?? 'normal',
        status: map['status'] as String? ?? 'open',
        lastMessageAt: DateTime.tryParse(map['last_message_at'] as String? ?? '') ?? DateTime.now(),
        closedAt: map['closed_at'] != null ? DateTime.tryParse(map['closed_at'] as String) : null,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  String get statusLabel => switch (status) {
        'open' => 'Ouvert',
        'pending' => 'En attente de vous',
        'resolved' => 'Résolu',
        'closed' => 'Fermé',
        _ => status,
      };

  bool get isClosed => status == 'closed';
}

const ticketCategoryLabel = {
  'account': 'Compte',
  'payment': 'Paiement',
  'ride': 'Course / livraison',
  'driver': 'Chauffeur',
  'passenger': 'Passager',
  'technical': 'Technique',
  'other': 'Autre',
};

class TicketMessage {
  final String id;
  final String ticketId;
  final String authorId;
  final String body;
  final bool isInternal;
  final DateTime createdAt;

  const TicketMessage({
    required this.id,
    required this.ticketId,
    required this.authorId,
    required this.body,
    required this.isInternal,
    required this.createdAt,
  });

  factory TicketMessage.fromMap(Map<String, dynamic> map) => TicketMessage(
        id: map['id'] as String,
        ticketId: map['ticket_id'] as String,
        authorId: map['author_id'] as String,
        body: map['body'] as String? ?? '',
        isInternal: map['is_internal'] as bool? ?? false,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}
