import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme/app_colors.dart';
import '../../data/models/driver_profile.dart';
import '../../data/models/active_ride.dart';
import '../../data/services/driver_backend.dart';
import 'location_reporter.dart';
import '../offers/pending_offer_card.dart';
import '../offers/open_delivery_card.dart';
import '../ride/active_ride_screen.dart';

/// Tableau de bord principal — reprend la structure de la page web
/// (routes/app/driver.tsx) : bloc "course(s) en cours" en priorité, puis
/// offre poussée (mode proximity) ou liste ouverte (mode self_assign) selon
/// ce que le moteur de dispatch propose, toggle en ligne/hors ligne, stats.
class DashboardScreen extends StatefulWidget {
  final DriverProfile profile;
  const DashboardScreen({super.key, required this.profile});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late bool _isOnline = widget.profile.isOnline;
  bool _togglingOnline = false;

  List<ActiveRide> _activeRides = [];
  List<OpenDelivery> _openDeliveries = [];
  PendingOffer? _pendingOffer;
  bool _loading = true;
  String? _error;

  int? _walletBalance;
  int? _totalEarnings;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _loadWalletStats();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshAll(silent: true));
  }

  /// Solde wallet + gains totaux — affichés sur le tableau de bord (pas
  /// seulement dans l'onglet Wallet) pour que le livreur voie sa situation
  /// financière avant même d'accepter une offre : un solde ≤ 0 bloque
  /// l'acceptation (voir wallet_balance_gating.sql), autant le savoir tout
  /// de suite plutôt qu'à l'échec de l'acceptation. Chargé séparément du
  /// polling 4s des offres (pas besoin d'un rafraîchissement aussi agressif
  /// pour des données financières).
  Future<void> _loadWalletStats() async {
    try {
      final results = await Future.wait([
        DriverBackend.fetchWalletBalance(),
        DriverBackend.fetchTotalEarnings(),
      ]);
      if (!mounted) return;
      setState(() {
        _walletBalance = results[0];
        _totalEarnings = results[1];
      });
    } catch (_) {
      // best-effort — l'onglet Wallet reste la source de vérité en cas d'échec ici.
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAll({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final active = await DriverBackend.fetchActiveRides();
      List<OpenDelivery> open = [];
      PendingOffer? offer;
      if (_isOnline && active.isEmpty) {
        offer = await DriverBackend.fetchPendingOffer();
        if (offer == null) {
          open = await DriverBackend.fetchOpenDeliveries(city: widget.profile.city);
        }
      }
      if (!mounted) return;
      setState(() {
        _activeRides = active;
        _openDeliveries = open;
        _pendingOffer = offer;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() => _togglingOnline = true);
    try {
      await DriverBackend.setOnline(value);
      setState(() => _isOnline = value);
      await _refreshAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _togglingOnline = false);
    }
  }

  Future<void> _acceptOpen(OpenDelivery d) async {
    try {
      final ok = await DriverBackend.acceptOpenRide(d.id);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Livraison acceptée !')));
        await _refreshAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trop tard — déjà prise par un autre livreur.')));
        await _refreshAll();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _acceptOffer(PendingOffer offer) async {
    try {
      await DriverBackend.acceptOffer(offer.rideId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Livraison acceptée !')));
      await _refreshAll();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _declineOffer(PendingOffer offer) async {
    try {
      await DriverBackend.declineOffer(offer.rideId);
    } catch (_) {
      // best-effort
    } finally {
      await _refreshAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: () => Future.wait([_refreshAll(), _loadWalletStats()]),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Icon(Icons.circle, size: 12, color: _isOnline ? AppColors.primaryGreen : AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isOnline ? 'En ligne' : 'Hors ligne',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                if (_togglingOnline)
                  const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Switch(value: _isOnline, onChanged: _toggleOnline),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Gains totaux', value: _totalEarnings == null ? '…' : _formatXof(_totalEarnings!))),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(label: 'Livraisons', value: '${widget.profile.ridesCount}')),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(label: 'Note', value: '${widget.profile.ratingAvg.toStringAsFixed(1)} / 5')),
            ],
          ),
          const SizedBox(height: 12),
          _WalletBanner(balance: _walletBalance),
          const SizedBox(height: 20),
          if (_activeRides.isNotEmpty) ...[
            const Text('Livraison en cours', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ..._activeRides.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ActiveRideScreen(ride: r)),
                    ).then((_) => _refreshAll()),
                    child: _ActiveRideSummaryCard(ride: r),
                  ),
                )),
          ] else if (!_isOnline) ...[
            const _EmptyBlock(text: 'Passez en ligne pour recevoir des livraisons.'),
          ] else if (_loading) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator())),
          ] else if (_pendingOffer != null) ...[
            PendingOfferCard(
              offer: _pendingOffer!,
              onAccept: () => _acceptOffer(_pendingOffer!),
              onDecline: () => _declineOffer(_pendingOffer!),
              onExpired: _refreshAll,
            ),
          ] else if (_openDeliveries.isNotEmpty) ...[
            const Text('Livraisons disponibles', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ..._openDeliveries.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OpenDeliveryCard(delivery: d, onAccept: () => _acceptOpen(d)),
                )),
          ] else ...[
            const _EmptyBlock(text: 'Aucune livraison en attente. Restez prêt !'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
          ],
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Courrier Livreur')),
      body: _isOnline ? LocationReporter(child: body) : body,
    );
  }
}

String _formatXof(num amount) {
  final s = amount.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${amount < 0 ? '-' : ''}$buf FCFA';
}

/// Bandeau solde wallet — visible directement sur le tableau de bord, avant
/// que le livreur essaie d'accepter une offre (voir WalletScreen pour
/// l'historique complet des mouvements). `null` = pas encore chargé, on
/// n'affiche rien plutôt qu'un faux zéro.
class _WalletBanner extends StatelessWidget {
  final int? balance;
  const _WalletBanner({required this.balance});

  @override
  Widget build(BuildContext context) {
    if (balance == null) return const SizedBox.shrink();
    final depleted = balance! <= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: depleted ? AppColors.accentRed.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: depleted ? Border.all(color: AppColors.accentRed) : null,
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet, color: depleted ? AppColors.accentRed : AppColors.textSecondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Solde wallet : ${_formatXof(balance!)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (depleted)
                  const Text(
                    "Solde épuisé — vous ne pourrez pas accepter de livraison tant qu'il n'est pas rechargé.",
                    style: TextStyle(fontSize: 12, color: AppColors.accentRed),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  final String text;
  const _EmptyBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}

class _ActiveRideSummaryCard extends StatelessWidget {
  final ActiveRide ride;
  const _ActiveRideSummaryCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.primaryGreenLight, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ride.status.label, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreenDark)),
          const SizedBox(height: 8),
          Text('Retrait : ${ride.pickupAddress}', maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Livraison : ${ride.dropoffAddress}', maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          const Align(alignment: Alignment.centerRight, child: Text('Voir détails →', style: TextStyle(color: AppColors.primaryGreenDark))),
        ],
      ),
    );
  }
}
