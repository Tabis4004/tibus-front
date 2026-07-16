/// Wallet points passager — voir `passenger_wallets` côté Tibus Ride.
/// Distinct du wallet FCFA chauffeur (`driver_wallets`, côté courrier_livreur) :
/// ici les points sont gagnés par parrainage et convertibles en crédit course
/// (reward_settings.point_value_xof), pas en FCFA directement.
class PassengerWallet {
  final int balancePts;
  const PassengerWallet({required this.balancePts});

  factory PassengerWallet.fromMap(Map<String, dynamic>? map) =>
      PassengerWallet(balancePts: (map?['balance_pts'] as num?)?.toInt() ?? 0);
}

/// Reflète l'enum Postgres `passenger_wallet_tx_type`, inchangé.
class PassengerWalletTx {
  final String id;
  final int amountPts;
  final String type;
  final String? notes;
  final DateTime createdAt;

  const PassengerWalletTx({
    required this.id,
    required this.amountPts,
    required this.type,
    this.notes,
    required this.createdAt,
  });

  factory PassengerWalletTx.fromMap(Map<String, dynamic> map) => PassengerWalletTx(
        id: map['id'] as String,
        amountPts: (map['amount_pts'] as num?)?.toInt() ?? 0,
        type: map['type'] as String? ?? 'adjustment',
        notes: map['notes'] as String?,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  String get typeLabel => switch (type) {
        'topup' => 'Recharge',
        'ride_earn' => 'Gagné sur une course',
        'referral_bonus' => 'Bonus de parrainage',
        'ride_redeem' => 'Utilisé sur une course',
        'refund' => 'Remboursement',
        _ => 'Ajustement',
      };
}

/// Un filleul parrainé — reflète `referrals` (référentiel : referrer_id =
/// l'utilisateur courant, referee_id = la personne parrainée).
class Referral {
  final String id;
  final String refereeRole;
  final String status;
  final int? rewardPts;
  final int? rewardXof;
  final DateTime createdAt;

  const Referral({
    required this.id,
    required this.refereeRole,
    required this.status,
    this.rewardPts,
    this.rewardXof,
    required this.createdAt,
  });

  factory Referral.fromMap(Map<String, dynamic> map) => Referral(
        id: map['id'] as String,
        refereeRole: map['referee_role'] as String? ?? '',
        status: map['status'] as String? ?? 'pending',
        rewardPts: (map['reward_pts'] as num?)?.toInt(),
        rewardXof: (map['reward_xof'] as num?)?.toInt(),
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  String get statusLabel => switch (status) {
        'validated' => 'Validé',
        'rewarded' => 'Récompensé',
        'cancelled' => 'Annulé',
        _ => 'En attente',
      };
}
