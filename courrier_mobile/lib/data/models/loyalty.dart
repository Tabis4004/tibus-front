class LoyaltyContext {
  final int pointsBalance;
  final int pointsEarnedTotal;
  final double redeemableValue;

  const LoyaltyContext({
    required this.pointsBalance,
    required this.pointsEarnedTotal,
    required this.redeemableValue,
  });

  factory LoyaltyContext.fromMap(Map<String, dynamic> map) => LoyaltyContext(
        pointsBalance: (map['pointsBalance'] as num?)?.toInt() ?? 0,
        pointsEarnedTotal: (map['pointsEarnedTotal'] as num?)?.toInt() ?? 0,
        redeemableValue: (map['redeemableValue'] as num?)?.toDouble() ?? 0,
      );
}

class PromoCode {
  final String id;
  final String code;
  final String discountType; // 'percentage' | 'fixed'
  final double discountValue;
  final bool isActive;
  final DateTime? expiresAt;

  const PromoCode({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.isActive,
    this.expiresAt,
  });

  factory PromoCode.fromMap(Map<String, dynamic> map) => PromoCode(
        id: map['id'] as String,
        code: map['code'] as String,
        discountType: map['discountType'] as String? ?? 'percentage',
        discountValue: (map['discountValue'] as num?)?.toDouble() ?? 0,
        isActive: map['isActive'] as bool? ?? true,
        expiresAt: map['expiresAt'] != null ? DateTime.tryParse(map['expiresAt'] as String) : null,
      );
}
