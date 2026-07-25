import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/providers.dart';
import '../../../core/config/colis_ui_config.dart';
import '../../../core/utils/connectivity.dart';
import '../../../data/models/colis.dart';
import '../../../data/models/pending_colis.dart';
import '../caisse/station_cash_screen.dart';
import 'colis_receipt_preview_sheet.dart';

/// Enregistrement d'un nouveau colis — appelle register_colis_autonome
/// tel quel (mêmes champs que le formulaire web ColisAutonomesPage.tsx),
/// gares/natures/caisse branchées sur les mêmes RPC (list_company_station_gares,
/// listNatures, get_open_station_cash_for_user).
class ColisCreateScreen extends ConsumerStatefulWidget {
  const ColisCreateScreen({super.key});

  @override
  ConsumerState<ColisCreateScreen> createState() => _ColisCreateScreenState();
}

class _ColisCreateScreenState extends ConsumerState<ColisCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomExp = TextEditingController();
  final _telExp = TextEditingController();
  final _nomDest = TextEditingController();
  final _telDest = TextEditingController();
  final _description = TextEditingController();
  final _poids = TextEditingController();
  final _pieces = TextEditingController(text: '1');
  final _montant = TextEditingController();
  final _valeurMarchandise = TextEditingController();
  final _pourcentagePercu = TextEditingController();
  bool _submitting = false;
  bool _montantAuto = false;
  ColisUiConfig _uiConfig = ColisUiConfig.defaults;

  bool _loadingRefs = true;
  String? _refsError;
  /// Compagnie effectivement utilisée pour cet écran, dérivée de la caisse
  /// réellement ouverte (voir _loadReferences) — ne PAS reconfondre avec
  /// activeCompanyIdProvider qui peut rester périmé si son invalidation a
  /// été manquée (état Riverpod caché, invalidé seulement à l'ouverture/
  /// fermeture de caisse).
  String? _companyId;
  List<GareOption> _gares = [];
  List<ColisNature> _natures = [];
  String? _gareDestinationId;
  String? _selectedNatureId;
  OpenStationCash? _openCash;
  double? _prixMinSuggere;
  /// Vrai quand _loadReferences a dû retomber sur le cache local (réseau
  /// indisponible) — affiche un bandeau "mode hors-ligne" et permet de
  /// savoir que l'enregistrement à venir sera mis en file d'attente plutôt
  /// qu'envoyé directement (voir ReferenceCacheService, _registerOffline).
  bool _offline = false;

  /// Photo optionnelle prise à l'enregistrement — voir _pickPhoto. Uploadée
  /// APRÈS la création du colis (a besoin de son id), une fois le reçu déjà
  /// généré : consultable ensuite sur ColisDetailScreen, jamais imprimée.
  Uint8List? _photoBytes;

  @override
  void initState() {
    super.initState();
    _valeurMarchandise.addListener(_recomputeMontantIfAuto);
    _pourcentagePercu.addListener(_recomputeMontantIfAuto);
    _poids.addListener(_refreshPrixMin);
    Future.microtask(_loadReferences);
  }

  @override
  void dispose() {
    _valeurMarchandise.removeListener(_recomputeMontantIfAuto);
    _pourcentagePercu.removeListener(_recomputeMontantIfAuto);
    _poids.removeListener(_refreshPrixMin);
    super.dispose();
  }

  Future<void> _loadReferences() async {
    setState(() {
      _loadingRefs = true;
      _refsError = null;
    });
    final service = ref.read(colisServiceProvider);
    final cache = ref.read(referenceCacheServiceProvider);
    // activeCompanyIdProvider peut lui-même échouer hors connexion (myRolesProvider
    // appelle fetchMyRoles() en réseau, sans catch, si jamais résolu avec
    // succès pendant cette session) — on l'isole pour ne pas faire planter
    // tout le rechargement des références en mode hors-ligne : le fallback
    // ci-dessous s'appuie alors uniquement sur la dernière caisse ouverte
    // connue en cache.
    String? fallbackCompanyId;
    try {
      fallbackCompanyId = await ref.read(activeCompanyIdProvider.future);
    } catch (_) {
      fallbackCompanyId = null;
    }
    if (!mounted) return;
    try {
      // La caisse réellement ouverte est l'unique source de vérité pour la
      // compagnie de travail de cet écran : on la récupère D'ABORD et on en
      // dérive companyId, puis on l'utilise pour les gares/natures/réglages.
      // Se fier à activeCompanyIdProvider pour ces appels (au lieu de
      // dériver depuis _openCash comme ici) pouvait renvoyer une compagnie
      // périmée si son invalidation avait été manquée quelque part — c'était
      // la cause du bug "Gare de départ (caisse ouverte) : Gare 2" alors que
      // la liste de destination affichait les gares d'une autre compagnie
      // (Gare Abobo, Gare Bouake) : deux appels indépendants pouvaient donc
      // désigner deux compagnies différentes.
      final openCash = await service.getOpenStationCash().timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final companyId = (openCash.open ? openCash.companyId : null) ?? fallbackCompanyId;
      if (companyId == null) {
        setState(() {
          _openCash = openCash;
          _loadingRefs = false;
        });
        return;
      }
      final results = await Future.wait([
        service.listGares(companyId),
        service.listNatures(companyId),
        service.getCompanyColisSettings(companyId),
      ]);
      if (!mounted) return;
      final gares = results[0] as List<GareOption>;
      final natures = results[1] as List<ColisNature>;
      final activeNatures = natures.where((n) => n.isActive).toList();
      final settings = results[2] as Map<String, dynamic>;
      final uiConfig = ColisUiConfig.fromSettings(settings);
      final defaultPct = (settings['colisPourcentagePercuGeneral'] as num?)?.toDouble();
      // Alimente le cache hors-ligne pour la prochaine fois que le réseau
      // sera indisponible (voir ReferenceCacheService, branche catch
      // ci-dessous) — c'est ce qui permet à l'écran de rester utilisable
      // sans connexion.
      await cache.saveGares(companyId, gares);
      await cache.saveNatures(companyId, natures);
      await cache.saveDefaultPct(companyId, defaultPct);
      await cache.saveOpenCash(openCash);
      setState(() {
        _companyId = companyId;
        _gares = gares;
        _natures = activeNatures;
        _openCash = openCash;
        _uiConfig = uiConfig;
        _offline = false;
        if (defaultPct != null && _pourcentagePercu.text.isEmpty) {
          _pourcentagePercu.text = defaultPct.toString();
        }
        _loadingRefs = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Réseau indisponible (ou erreur quelconque) : on retombe sur le
      // dernier instantané connu plutôt que de bloquer tout l'écran — sans
      // ça, un agent hors connexion ne pourrait même pas ouvrir le
      // formulaire (voir demande "enregistrement même sans connexion").
      final cachedOpenCash = await cache.loadOpenCash();
      final companyId = cachedOpenCash?.companyId ?? fallbackCompanyId;
      final cachedGares = companyId == null ? null : await cache.loadGares(companyId);
      final cachedNatures = companyId == null ? null : await cache.loadNatures(companyId);
      if (!mounted) return;
      if (companyId == null ||
          cachedOpenCash == null ||
          !cachedOpenCash.open ||
          cachedGares == null ||
          cachedGares.isEmpty ||
          cachedNatures == null ||
          cachedNatures.isEmpty) {
        setState(() {
          _refsError = '$e';
          _loadingRefs = false;
        });
        return;
      }
      final cachedPct = await cache.loadDefaultPct(companyId);
      if (!mounted) return;
      setState(() {
        _companyId = companyId;
        _gares = cachedGares;
        _natures = cachedNatures.where((n) => n.isActive).toList();
        _openCash = cachedOpenCash;
        _offline = true;
        if (cachedPct != null && _pourcentagePercu.text.isEmpty) {
          _pourcentagePercu.text = cachedPct.toString();
        }
        _loadingRefs = false;
      });
    }
  }

  Future<void> _refreshPrixMin() async {
    // Priorité à _companyId (résolu depuis la caisse ouverte, voir
    // _loadReferences) pour rester cohérent avec les gares/natures affichées.
    final companyId = _companyId ?? await ref.read(activeCompanyIdProvider.future);
    if (!mounted) return;
    if (companyId == null || _selectedNatureId == null) {
      setState(() => _prixMinSuggere = null);
      return;
    }
    try {
      final min = await ref.read(colisServiceProvider).getColisPrixMin(
            companyId: companyId,
            natureIds: [_selectedNatureId!],
            poidsKg: double.tryParse(_poids.text),
          );
      if (mounted) setState(() => _prixMinSuggere = min > 0 ? min : null);
    } catch (_) {
      if (mounted) setState(() => _prixMinSuggere = null);
    }
  }

  void _recomputeMontantIfAuto() {
    if (!_montantAuto) return;
    final valeur = double.tryParse(_valeurMarchandise.text) ?? 0;
    final pct = double.tryParse(_pourcentagePercu.text) ?? 0;
    if (valeur <= 0 || pct <= 0) {
      _montant.text = '';
      return;
    }
    var calcule = (valeur * pct / 100).round();
    if (_prixMinSuggere != null && calcule < _prixMinSuggere!) {
      calcule = _prixMinSuggere!.round();
    }
    _montant.text = calcule.toString();
  }

  List<GareOption> get _destinationGares =>
      _gares.where((g) => g.id != _openCash?.gareId).toList();

  /// Prend/choisit une photo du colis — bouton "optionnel" au formulaire.
  /// image_picker gère aussi bien caméra que galerie et fonctionne sur
  /// Flutter Web (input file caché), même déploiement que le reste de
  /// l'écran (voir pubspec.yaml).
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1600);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (mounted) setState(() => _photoBytes = bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible de charger la photo : $e')));
      }
    }
  }

  Future<void> _submit(String companyId) async {
    if (!_formKey.currentState!.validate()) return;
    final gareDepartId = _openCash?.gareId;
    if (gareDepartId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ouvrez votre caisse avant d\'enregistrer un colis.'),
      ));
      return;
    }
    if (_gareDestinationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sélectionnez la gare de destination.'),
      ));
      return;
    }
    if (_selectedNatureId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sélectionnez une nature de colis.'),
      ));
      return;
    }
    final valeur = double.tryParse(_valeurMarchandise.text) ?? 0;
    if (valeur <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Valeur marchandise obligatoire — sert de base au remboursement en cas de perte.'),
      ));
      return;
    }
    if (_montantAuto && (double.tryParse(_pourcentagePercu.text) ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Renseignez le pourcentage perçu pour le calcul automatique.'),
      ));
      return;
    }
    final montant = double.tryParse(_montant.text) ?? 0;
    if (_prixMinSuggere != null && montant < _prixMinSuggere!) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Montant fret insuffisant — minimum requis ${_prixMinSuggere!.toStringAsFixed(0)} FCFA.'),
      ));
      return;
    }
    final input = RegisterColisInput(
      companyId: companyId,
      gareDepartId: gareDepartId,
      gareDestinationId: _gareDestinationId!,
      nomExpediteur: _nomExp.text.trim(),
      telephoneExpediteur: _telExp.text.trim(),
      nomDestinataire: _nomDest.text.trim(),
      telephoneDestinataire: _telDest.text.trim(),
      descriptionContenu: _uiConfig.showFormField('description') && _description.text.trim().isNotEmpty
          ? _description.text.trim()
          : null,
      poidsKg: _uiConfig.showFormField('poids') ? double.tryParse(_poids.text) : null,
      nombrePieces: _uiConfig.showFormField('pieces') ? (int.tryParse(_pieces.text) ?? 1) : 1,
      montantFret: montant,
      valeurMarchandise: valeur,
      pourcentagePercu: _uiConfig.showFormField('pourcentagePercu') && _montantAuto
          ? double.tryParse(_pourcentagePercu.text)
          : null,
      natureIds: [_selectedNatureId!],
    );
    setState(() => _submitting = true);
    try {
      // Pas de réseau détecté : on n'essaie même pas l'appel RPC (évite
      // d'attendre un timeout) et on part directement en file d'attente
      // locale (voir demande "enregistrement même sans connexion").
      if (!await hasNetworkConnection()) {
        await _registerOffline(input);
        return;
      }
      try {
        final result = await ref.read(colisServiceProvider).registerColis(input).timeout(const Duration(seconds: 15));
        if (!mounted) return;
        final colisId = result['id'] as String;
        unawaited(ref.read(staffNotificationsServiceProvider).notifyFromRpcResult(
              result,
              companyId: companyId,
            ));
        String? photoPath;
        if (_uiConfig.showFormField('photo') && _photoBytes != null) {
          // Best-effort : un échec d'upload de la photo ne doit jamais bloquer
          // l'enregistrement du colis (déjà créé et payé à ce stade) ni
          // empêcher l'aperçu/impression du reçu.
          try {
            final service = ref.read(colisServiceProvider);
            photoPath = await service.uploadColisPhoto(
              companyId: companyId,
              colisId: colisId,
              bytes: _photoBytes!,
            );
            await service.setColisPhoto(colisId, photoPath);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Colis enregistré, mais échec de l\'ajout de la photo : $e')),
              );
            }
          }
        }
        // Aperçu du reçu (avec choix d'imprimante) ouvert automatiquement
        // après l'enregistrement — même parcours que le web (ColisReceiptPanel
        // autoPrint). Avant : simple pop, aucun aperçu proposé.
        final now = DateTime.now();
        var colis = Colis(
          id: result['id'] as String,
          statut: ColisStatutX.fromDb(result['statutColis'] as String? ?? 'enregistre'),
          nomExpediteur: input.nomExpediteur,
          telephoneExpediteur: input.telephoneExpediteur,
          nomDestinataire: input.nomDestinataire,
          telephoneDestinataire: input.telephoneDestinataire,
          descriptionContenu: input.descriptionContenu,
          poidsKg: input.poidsKg,
          nombrePieces: input.nombrePieces,
          montantFret: input.montantFret,
          valeurMarchandise: input.valeurMarchandise,
          pourcentagePercu: input.pourcentagePercu,
          createdAt: now,
          updatedAt: now,
          gareDepart: _openCash?.gareName ?? '',
          gareDestination: _gares
              .firstWhere((g) => g.id == _gareDestinationId,
                  orElse: () => const GareOption(id: '', name: ''))
              .name,
          natures: [
            for (final n in _natures)
              if (n.id == _selectedNatureId) n.libelle,
          ],
        );
        // register_colis_autonome ne renvoie que id/statutColis/montantFret/sms
        // (voir migration 169) — ni les téléphones gare/compagnie ni le nom de
        // la compagnie, d'où leur absence sur le reçu imprimé juste après
        // l'enregistrement malgré colis_receipt_lines.dart/printer_service.dart
        // qui savent déjà les afficher. On recharge le détail complet (même
        // RPC get_colis_autonome_detail que ColisDetailScreen) pour que ces
        // champs soient bien renseignés sur le tout premier reçu, sans
        // attendre que l'agent rouvre le colis depuis la liste.
        try {
          final detail = await ref.read(colisServiceProvider).getColisDetail(colisId);
          if (detail != null) colis = Colis.fromMap(detail);
        } catch (_) {
          // Best-effort : le colis est déjà enregistré/payé à ce stade — un
          // échec de rechargement du détail ne doit pas bloquer l'aperçu du
          // reçu, qui retombe alors sur les données locales ci-dessus.
        }
        // Alimente le cache nom/téléphone compagnie (voir
        // ReferenceCacheService.saveCompanyInfo) pour que le PROCHAIN reçu
        // provisoire (enregistrement hors-ligne) affiche le bon en-tête,
        // même si l'agent n'a jamais ouvert le détail d'un colis.
        if (colis.companyName.isNotEmpty || colis.companyPhone.isNotEmpty) {
          await ref.read(referenceCacheServiceProvider).saveCompanyInfo(
                companyId,
                name: colis.companyName,
                phone: colis.companyPhone,
              );
        }
        await showColisReceiptPreview(context, colis);
        if (mounted) Navigator.of(context).pop();
      } on TimeoutException {
        await _registerOffline(input);
      } on SocketException {
        await _registerOffline(input);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Enregistrement hors-ligne — met le colis en file d'attente locale
  /// (voir SyncService/OfflineQueueService) au lieu d'appeler
  /// register_colis_autonome, puis affiche/imprime immédiatement un reçu
  /// marqué "PROVISOIRE" (voir Colis.isPendingSync, colisReceiptLines) :
  /// l'agent peut ainsi encaisser et servir le client tout de suite, la
  /// vraie référence étant confirmée automatiquement dès que le réseau
  /// revient (AgentShell écoute la connectivité).
  Future<void> _registerOffline(RegisterColisInput input) async {
    final cache = ref.read(referenceCacheServiceProvider);
    final companyInfo = await cache.loadCompanyInfo(input.companyId);
    final natureLabel = _natures
        .where((n) => input.natureIds.contains(n.id))
        .map((n) => n.libelle)
        .join(', ');
    final gareDestinationName = _gares
        .firstWhere((g) => g.id == input.gareDestinationId, orElse: () => const GareOption(id: '', name: ''))
        .name;
    final pending = PendingColis(
      localId: generateLocalId(),
      createdAt: DateTime.now(),
      companyId: input.companyId,
      gareDepartId: input.gareDepartId,
      gareDestinationId: input.gareDestinationId,
      nomExpediteur: input.nomExpediteur,
      telephoneExpediteur: input.telephoneExpediteur,
      nomDestinataire: input.nomDestinataire,
      telephoneDestinataire: input.telephoneDestinataire,
      descriptionContenu: input.descriptionContenu,
      poidsKg: input.poidsKg,
      nombrePieces: input.nombrePieces,
      montantFret: input.montantFret,
      valeurMarchandise: input.valeurMarchandise,
      pourcentagePercu: input.pourcentagePercu,
      busId: input.busId,
      natureIds: input.natureIds,
      gareDepartName: _openCash?.gareName ?? '',
      gareDestinationName: gareDestinationName,
      companyName: companyInfo.name,
      companyPhone: companyInfo.phone,
      natureLabel: natureLabel,
      photoBase64: _photoBytes != null ? base64Encode(_photoBytes!) : null,
    );
    await ref.read(syncServiceProvider).enqueue(pending);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Pas de connexion — colis enregistré localement, sera synchronisé automatiquement.'),
    ));
    await showColisReceiptPreview(context, pending.toColis());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau colis')),
      body: companyIdAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (companyId) {
          if (companyId == null) {
            return const Center(child: Text('Aucun rôle actif.'));
          }
          if (_loadingRefs) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_refsError != null) {
            return _ErrorRetry(message: _refsError!, onRetry: _loadReferences);
          }
          if (_openCash == null || !_openCash!.open) {
            return _NoOpenCashCard(onRetry: _loadReferences);
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_offline)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.cloud_off_outlined, color: Colors.deepOrange, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Mode hors-ligne : le colis sera enregistré localement et synchronisé dès le retour du réseau.',
                            style: TextStyle(color: Colors.deepOrange, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                Card(
                  color: Colors.grey.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.store_mall_directory_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Gare de départ (caisse ouverte) : ${_openCash!.gareName ?? '—'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _gareDestinationId,
                  decoration: const InputDecoration(labelText: 'Gare de destination'),
                  items: _destinationGares
                      .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _gareDestinationId = v),
                  validator: (v) => v == null ? 'Champ requis' : null,
                ),
                const SizedBox(height: 20),
                const Text('Expéditeur', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(controller: _nomExp, decoration: const InputDecoration(labelText: 'Nom'), validator: _required),
                const SizedBox(height: 10),
                TextFormField(controller: _telExp, decoration: const InputDecoration(labelText: 'Téléphone'), keyboardType: TextInputType.phone, validator: _required),
                const SizedBox(height: 20),
                const Text('Destinataire', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(controller: _nomDest, decoration: const InputDecoration(labelText: 'Nom'), validator: _required),
                const SizedBox(height: 10),
                TextFormField(controller: _telDest, decoration: const InputDecoration(labelText: 'Téléphone'), keyboardType: TextInputType.phone, validator: _required),
                const SizedBox(height: 20),
                const Text('Colis', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedNatureId,
                  decoration: const InputDecoration(labelText: 'Nature de colis'),
                  items: _natures
                      .map((n) => DropdownMenuItem(value: n.id, child: Text(n.libelle)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedNatureId = v);
                    _refreshPrixMin();
                  },
                  validator: (v) => v == null ? 'Champ requis' : null,
                ),
                const SizedBox(height: 10),
                if (_uiConfig.showFormField('description')) ...[
                  TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description du contenu')),
                  const SizedBox(height: 10),
                ],
                if (_uiConfig.showFormField('poids') || _uiConfig.showFormField('pieces')) ...[
                  Row(
                    children: [
                      if (_uiConfig.showFormField('poids'))
                        Expanded(child: TextFormField(controller: _poids, decoration: const InputDecoration(labelText: 'Poids (kg)'), keyboardType: TextInputType.number)),
                      if (_uiConfig.showFormField('poids') && _uiConfig.showFormField('pieces')) const SizedBox(width: 10),
                      if (_uiConfig.showFormField('pieces'))
                        Expanded(child: TextFormField(controller: _pieces, decoration: const InputDecoration(labelText: 'Nombre de pièces'), keyboardType: TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  controller: _valeurMarchandise,
                  decoration: const InputDecoration(
                    labelText: 'Valeur marchandise (FCFA) *',
                    helperText: 'Obligatoire — sert de base au remboursement en cas de perte.',
                    helperMaxLines: 2,
                  ),
                  keyboardType: TextInputType.number,
                  validator: _required,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_uiConfig.showFormField('pourcentagePercu'))
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Calcul automatique du montant fret'),
                            subtitle: const Text('Montant fret = pourcentage perçu × valeur marchandise'),
                            value: _montantAuto,
                            onChanged: (v) => setState(() {
                              _montantAuto = v;
                              _recomputeMontantIfAuto();
                            }),
                          ),
                        if (_uiConfig.showFormField('pourcentagePercu') && _montantAuto) ...[
                          TextFormField(
                            controller: _pourcentagePercu,
                            decoration: const InputDecoration(labelText: 'Pourcentage perçu (%)'),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _recomputeMontantIfAuto(),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextFormField(
                          controller: _montant,
                          decoration: InputDecoration(
                            labelText: 'Montant fret (FCFA)',
                            filled: _montantAuto,
                            helperText: _prixMinSuggere != null
                                ? 'Minimum requis pour cette nature : ${_prixMinSuggere!.toStringAsFixed(0)} FCFA'
                                : null,
                            helperMaxLines: 2,
                          ),
                          keyboardType: TextInputType.number,
                          enabled: !_montantAuto,
                          validator: _required,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_uiConfig.showFormField('photo')) ...[
                  const SizedBox(height: 20),
                  const Text('Photo du colis (optionnel)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    'Consultable sur le détail du colis — non imprimée sur le reçu.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (_photoBytes != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_photoBytes!, height: 160, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('Prendre une photo'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickPhoto(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
                          label: const Text('Galerie'),
                        ),
                      ),
                      if (_photoBytes != null)
                        IconButton(
                          tooltip: 'Retirer la photo',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _photoBytes = null),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  // _companyId (dérivé de la caisse ouverte) prioritaire sur
                  // companyId (activeCompanyIdProvider, potentiellement
                  // périmé) — garantit que l'enregistrement utilise la même
                  // compagnie que la gare de départ affichée.
                  onPressed: _submitting ? null : () => _submit(_companyId ?? companyId),
                  child: _submitting
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Enregistrer le colis'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null;
}

class _NoOpenCashCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoOpenCashCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.point_of_sale_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Aucune caisse ouverte',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'L\'enregistrement d\'un colis nécessite une caisse (gare) ouverte.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StationCashScreen()),
                );
                onRetry();
              },
              icon: const Icon(Icons.point_of_sale_outlined),
              label: const Text('Ouvrir ma caisse'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Erreur : $message', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
