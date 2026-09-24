import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_recette.dart';
import '../../data/models/embarquement_session.dart';

/// Tableau de bord des recettes — troisième rapport du module.
///
/// Rassemble les rapports de recette (embarquement_recette) de toutes les
/// sessions du périmètre de l'utilisateur, avec un filtre par gare et par
/// période, regroupés par gare de départ ou par itinéraire.
///
/// Périmètre (voir recetteDashboardAccessProvider) :
///  - owner : toutes les gares de la compagnie, filtre « Toutes les gares » ;
///  - gérant / comptable de gare : leur seule gare. Ses sessions sont
///    filtrées ici ET on ne demande jamais la recette d'une session hors
///    périmètre ; le serveur reste l'autorité (RPC restreintes par gare).
///
/// Le total est la somme des recettes de session : il ne peut pas diverger de
/// ce que lit l'agent sur le rapport de recette d'une session.
///
/// Pas de RPC dédiée : on réutilise embarquement_list_sessions et
/// embarquement_recette. Coût : une requête par session de la période, par
/// lots de [_batchSize]. Si le volume devient important, une RPC d'agrégation
/// côté serveur sera plus adaptée.
///
/// Honnêteté des chiffres : une session dont la recette n'a pas pu être lue
/// n'est jamais comptée comme 0 — elle est signalée et le total est présenté
/// comme incomplet.
enum _Regroupement { gare, itineraire }

enum _Preset { aujourdhui, sept, mois, perso }

class _SessionRecette {
  final EmbarquementSession session;
  final EmbarquementRecette? recette;
  final Object? error;
  const _SessionRecette(this.session, {this.recette, this.error});
}

class _Groupe {
  final String cle;
  final String libelle;
  final List<_SessionRecette> items = [];
  _Groupe(this.cle, this.libelle);

  Iterable<EmbarquementRecette> get _recettes =>
      items.where((i) => i.recette != null).map((i) => i.recette!);

  int get sessions => items.length;
  int get boarded => _recettes.fold(0, (s, r) => s + r.boarded);
  int get withoutAmount => _recettes.fold(0, (s, r) => s + r.withoutAmount);
  num get total => _recettes.fold<num>(0, (s, r) => s + r.total);
  int get enErreur => items.where((i) => i.error != null).length;
}

class RecetteDashboardScreen extends ConsumerStatefulWidget {
  final RecetteDashboardAccess access;
  final String? companyName;
  const RecetteDashboardScreen({super.key, required this.access, this.companyName});

  @override
  ConsumerState<RecetteDashboardScreen> createState() => _RecetteDashboardScreenState();
}

class _RecetteDashboardScreenState extends ConsumerState<RecetteDashboardScreen> {
  static const _batchSize = 5;

  _Preset _preset = _Preset.aujourdhui;
  late DateTimeRange _periode = _rangeFor(_Preset.aujourdhui);
  _Regroupement _regroupement = _Regroupement.gare;

  /// null = toutes les gares du périmètre.
  String? _gareFilter;

  late final Map<String, String> _gares = {
    for (final g in widget.access.gares) g.id: g.label,
  };

  List<EmbarquementSession> _sessions = const [];
  bool _sessionsLoaded = false;
  // Recettes des sessions CLÔTURÉES déjà lues : figées, inutile de les
  // relire quand on change de période. Les sessions ouvertes sont toujours
  // relues (chiffres provisoires).
  final Map<String, EmbarquementRecette> _cache = {};

  /// Sessions du périmètre sur la période (toutes gares confondues) ; le
  /// filtre par gare s'applique ensuite sans nouvelle requête.
  List<_SessionRecette> _resultats = const [];

  bool _loading = true;
  bool _exporting = false;
  String? _fatalError;
  int _done = 0;
  int _todo = 0;
  DateTime _generatedAt = DateTime.now();

  static DateTimeRange _rangeFor(_Preset p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (p) {
      case _Preset.sept:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);
      case _Preset.mois:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
      case _Preset.aujourdhui:
      case _Preset.perso:
        return DateTimeRange(start: today, end: today);
    }
  }

  @override
  void initState() {
    super.initState();
    // Un gérant ou un comptable n'a qu'une gare : pas de choix à faire.
    if (!widget.access.isOwner && widget.access.gares.length == 1) {
      _gareFilter = widget.access.gares.first.id;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  // Périmètre ----------------------------------------------------------------

  bool _inScope(EmbarquementSession s) {
    if (widget.access.isOwner) return true;
    final g = s.gareId;
    return g != null && _gares.containsKey(g);
  }

  bool _inPeriode(EmbarquementSession s) {
    final debut = DateTime(_periode.start.year, _periode.start.month, _periode.start.day);
    final fin = DateTime(_periode.end.year, _periode.end.month, _periode.end.day)
        .add(const Duration(days: 1));
    final d = s.openedAt.toLocal();
    return !d.isBefore(debut) && d.isBefore(fin);
  }

  // Chargement -----------------------------------------------------------------

  Future<void> _loadAll({bool force = false}) async {
    setState(() {
      _loading = true;
      _fatalError = null;
      _done = 0;
      _todo = 0;
    });
    try {
      if (force) _cache.clear();
      if (force || !_sessionsLoaded) {
        _sessions = await ref
            .read(embarquementServiceProvider)
            .listSessions(companyId: widget.access.companyId, status: 'all');
        _sessionsLoaded = true;
      }
      await _loadRecettes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fatalError = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadRecettes() async {
    final service = ref.read(embarquementServiceProvider);
    final visibles = _sessions.where((s) => _inScope(s) && _inPeriode(s)).toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    final aLire = visibles.where((s) => s.isOpen || !_cache.containsKey(s.id)).toList();

    if (!mounted) return;
    setState(() {
      _loading = true;
      _done = 0;
      _todo = aLire.length;
    });

    final erreurs = <String, Object>{};
    for (var i = 0; i < aLire.length; i += _batchSize) {
      final lot = aLire.skip(i).take(_batchSize).toList();
      await Future.wait(lot.map((s) async {
        try {
          _cache[s.id] = await service.recette(s.id);
        } catch (e) {
          erreurs[s.id] = e;
          _cache.remove(s.id);
        }
      }));
      if (!mounted) return;
      setState(() => _done = (i + lot.length).clamp(0, aLire.length).toInt());
    }

    final resultats = visibles.map((s) {
      final r = _cache[s.id];
      return r != null
          ? _SessionRecette(s, recette: r)
          : _SessionRecette(s, error: erreurs[s.id] ?? 'Recette indisponible');
    }).toList();

    if (!mounted) return;
    setState(() {
      _resultats = resultats;
      _generatedAt = DateTime.now();
      _loading = false;
    });
  }

  Future<void> _setPreset(_Preset p) async {
    if (p == _Preset.perso) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: _periode,
        helpText: 'Période des sessions',
        saveText: 'Valider',
      );
      if (picked == null) return;
      setState(() {
        _preset = p;
        _periode = picked;
      });
    } else {
      setState(() {
        _preset = p;
        _periode = _rangeFor(p);
      });
    }
    await _loadRecettes();
  }

  // Vue filtrée ------------------------------------------------------------------

  List<_SessionRecette> get _vue => _gareFilter == null
      ? _resultats
      : _resultats.where((i) => i.session.gareId == _gareFilter).toList();

  Iterable<EmbarquementRecette> get _recettes =>
      _vue.where((i) => i.recette != null).map((i) => i.recette!);
  num get _total => _recettes.fold<num>(0, (s, r) => s + r.total);
  num get _totalTibus => _recettes.fold<num>(0, (s, r) => s + r.totalTibus);
  num get _totalExternal => _recettes.fold<num>(0, (s, r) => s + r.totalExternal);
  int get _boarded => _recettes.fold(0, (s, r) => s + r.boarded);
  int get _withoutAmount => _recettes.fold(0, (s, r) => s + r.withoutAmount);
  int get _enCours => _vue.where((i) => i.session.isOpen).length;
  List<_SessionRecette> get _enErreur => _vue.where((i) => i.error != null).toList();

  String _libelleGare(String? gareId) {
    if (gareId == null) return 'Gare non renseignée';
    return _gares[gareId] ?? 'Gare inconnue';
  }

  List<_Groupe> _groupesDe(List<_SessionRecette> source) {
    final map = <String, _Groupe>{};
    for (final item in source) {
      final s = item.session;
      final String cle;
      final String libelle;
      if (_regroupement == _Regroupement.gare) {
        cle = s.gareId ?? '_none';
        libelle = _libelleGare(s.gareId);
      } else {
        final label = s.routeLabel.trim();
        cle = label.toLowerCase();
        libelle = label.isEmpty ? 'Sans itinéraire' : label;
      }
      map.putIfAbsent(cle, () => _Groupe(cle, libelle)).items.add(item);
    }
    final liste = map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
    return liste;
  }

  List<_Groupe> get _groupes => _groupesDe(_vue);

  String get _titreRegroupement =>
      _regroupement == _Regroupement.gare ? 'gare de départ' : 'itinéraire';

  String get _portee {
    if (_gareFilter != null) return 'Gare : ${_libelleGare(_gareFilter)}';
    return widget.access.isOwner ? 'Toutes les gares' : 'Mes gares';
  }

  String get _periodeTexte {
    final f = DateFormat('dd/MM/yyyy');
    if (_periode.start == _periode.end) return 'le ${f.format(_periode.start)}';
    return 'du ${f.format(_periode.start)} au ${f.format(_periode.end)}';
  }

  String get _periodeCourte => switch (_preset) {
        _Preset.aujourdhui => "Aujourd'hui",
        _Preset.sept => '7 derniers jours',
        _Preset.mois => 'Ce mois',
        _Preset.perso => _periodeTexte,
      };

  // Détail par gare (fenêtre) ----------------------------------------------------

  void _showDetailParGare() {
    // Toutes les gares du périmètre, même à zéro : c'est le sens de ce
    // détail — voir d'un coup d'œil laquelle n'a rien encaissé. Ignore le
    // filtre de gare, qui restreint le reste de l'écran.
    final parGare = <String?, _Groupe>{};
    for (final g in widget.access.gares) {
      parGare[g.id] = _Groupe(g.id, g.label);
    }
    for (final item in _resultats) {
      final id = item.session.gareId;
      if (id != null && parGare.containsKey(id)) {
        parGare[id]!.items.add(item);
      } else if (widget.access.isOwner) {
        parGare.putIfAbsent(id, () => _Groupe(id ?? '_none', _libelleGare(id))).items.add(item);
      }
    }
    final liste = parGare.values.toList()
      ..sort((a, b) {
        final c = b.total.compareTo(a.total);
        return c != 0 ? c : a.libelle.compareTo(b.libelle);
      });

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recette — détail par gare\n$_periodeCourte',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  itemCount: liste.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final g = liste[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.location_city, color: AppColors.textSecondary),
                      title: Text(g.libelle, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${g.sessions} session${g.sessions > 1 ? "s" : ""} · '
                        '${g.boarded} embarquement${g.boarded > 1 ? "s" : ""}'
                        '${g.enErreur > 0 ? " · ${g.enErreur} non lue${g.enErreur > 1 ? "s" : ""}" : ""}',
                      ),
                      trailing: Text(
                        formatMontant(g.total),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Exports ------------------------------------------------------------------------

  String get _slug {
    final f = DateFormat('yyyyMMdd');
    return 'recette_${_regroupement.name}_${f.format(_periode.start)}_${f.format(_periode.end)}';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      await Printing.sharePdf(bytes: await _buildPdf(), filename: '$_slug.pdf');
    } catch (e) {
      _showError('Export PDF impossible : $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(_buildCsv())),
            mimeType: 'text/csv',
            name: '$_slug.csv',
          ),
        ],
        subject: 'Recette embarquement — $_periodeTexte',
      );
    } catch (e) {
      _showError('Export CSV impossible : $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _csvCell(String value) =>
      value.contains(RegExp(r'[";\n]')) ? '"${value.replaceAll('"', '""')}"' : value;

  String _buildCsv() {
    final dt = DateFormat('dd/MM/yyyy HH:mm');
    final groupes = _groupes;
    final vue = _vue;
    final rows = <List<String>>[
      ['Rapport de recette - tableau de bord'],
      if (widget.companyName != null) ['Compagnie', widget.companyName!],
      ['Perimetre', _portee],
      ['Regroupement', _regroupement == _Regroupement.gare ? 'Gare de depart' : 'Itineraire'],
      ['Periode', _periodeTexte],
      ['Edite le', dt.format(_generatedAt)],
      [],
      [
        _regroupement == _Regroupement.gare ? 'Gare de depart' : 'Itineraire',
        'Sessions',
        'Embarquements',
        'Total',
        'Sans montant connu',
        'Sessions non lues',
      ],
      ...groupes.map((g) => [
            g.libelle,
            '${g.sessions}',
            '${g.boarded}',
            montantCsv(g.total),
            '${g.withoutAmount}',
            '${g.enErreur}',
          ]),
      [
        'TOTAL',
        '${vue.length}',
        '$_boarded',
        montantCsv(_total),
        '$_withoutAmount',
        '${_enErreur.length}',
      ],
      ['Dont Tibus', '', '', montantCsv(_totalTibus)],
      ['Dont externes', '', '', montantCsv(_totalExternal)],
      [],
      ['Detail par session'],
      [
        'Gare de depart',
        'Itineraire',
        'Bus',
        'Ouverte le',
        'Statut',
        'Embarquements',
        'Total',
        'Sans montant connu',
      ],
      ...vue.map((i) {
        final s = i.session;
        final r = i.recette;
        return [
          _libelleGare(s.gareId),
          s.routeLabel,
          s.busLabel ?? '',
          dt.format(s.openedAt.toLocal()),
          s.isOpen ? 'En cours (provisoire)' : 'Cloturee',
          r == null ? 'NON LU' : '${r.boarded}',
          r == null ? '' : montantCsv(r.total),
          r == null ? '' : '${r.withoutAmount}',
        ];
      }),
    ];
    return rows.map((row) => row.map(_csvCell).join(';')).join('\n');
  }

  Future<Uint8List> _buildPdf() async {
    final dt = DateFormat('dd/MM/yyyy HH:mm');
    final groupes = _groupes;
    final doc = pw.Document();

    pw.Widget cellule(String texte, {bool gras = false, bool droite = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(
            texte,
            textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );

    final erreurs = _enErreur;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text('Rapport de recette — tableau de bord',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          if (widget.companyName != null)
            pw.Text(widget.companyName!, style: const pw.TextStyle(fontSize: 14)),
          pw.Text('$_portee — par $_titreRegroupement — $_periodeTexte',
              style: const pw.TextStyle(fontSize: 10)),
          if (_enCours > 0)
            pw.Text(
              '$_enCours session${_enCours > 1 ? "s" : ""} en cours — chiffres provisoires.',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey400),
            columnWidths: const {
              0: pw.FlexColumnWidth(6),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(3),
              3: pw.FlexColumnWidth(4),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cellule(_regroupement == _Regroupement.gare ? 'Gare de départ' : 'Itinéraire',
                      gras: true),
                  cellule('Sessions', gras: true, droite: true),
                  cellule('Embarq.', gras: true, droite: true),
                  cellule('Recette', gras: true, droite: true),
                ],
              ),
              if (groupes.isEmpty)
                pw.TableRow(children: [
                  cellule('Aucune session sur la période.'),
                  cellule('', droite: true),
                  cellule('', droite: true),
                  cellule('', droite: true),
                ]),
              ...groupes.map((g) => pw.TableRow(children: [
                    cellule(g.libelle),
                    cellule('${g.sessions}', droite: true),
                    cellule('${g.boarded}', droite: true),
                    cellule(formatMontant(g.total), droite: true),
                  ])),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cellule('TOTAL', gras: true),
                  cellule('${_vue.length}', gras: true, droite: true),
                  cellule('$_boarded', gras: true, droite: true),
                  cellule(formatMontant(_total), gras: true, droite: true),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Dont Tibus ${formatMontant(_totalTibus)} et externes ${formatMontant(_totalExternal)}.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          if (_withoutAmount > 0)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                '$_withoutAmount embarquement${_withoutAmount > 1 ? "s" : ""} sans montant connu — '
                'le total ne les compte pas.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.red800),
              ),
            ),
          if (erreurs.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                '${erreurs.length} session${erreurs.length > 1 ? "s" : ""} non lue'
                '${erreurs.length > 1 ? "s" : ""} — total INCOMPLET.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.red800),
              ),
            ),
          pw.SizedBox(height: 20),
          pw.Text('Édité par Tibus Embarquement le ${dt.format(_generatedAt)}',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );

    return doc.save();
  }

  // UI ---------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pret = !_loading && _fatalError == null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Recettes'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              [
                if (widget.companyName != null) widget.companyName!,
                widget.access.isOwner ? 'Vue propriétaire' : 'Vue de ma gare',
              ].join(' · '),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.ios_share),
            tooltip: 'Exporter',
            enabled: pret && !_exporting,
            onSelected: (value) {
              if (value == 'pdf') _exportPdf();
              if (value == 'csv') _exportCsv();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Exporter en PDF')),
              PopupMenuItem(value: 'csv', child: Text('Exporter en CSV')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadAll(force: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_fatalError != null) {
      return ListView(children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erreur : $_fatalError', textAlign: TextAlign.center),
        ),
      ]);
    }

    final groupes = _groupes;
    final erreurs = _enErreur;
    final montre = !_loading || _resultats.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (montre) ...[
          _cartesResume(),
          const SizedBox(height: 14),
        ],
        _filtres(),
        const SizedBox(height: 12),
        if (_loading) ...[
          LinearProgressIndicator(value: _todo == 0 ? null : _done / _todo),
          const SizedBox(height: 6),
          Text(
            _todo == 0 ? 'Chargement…' : 'Lecture des recettes : $_done / $_todo sessions',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
        ],
        if (montre) ...[
          if (_withoutAmount > 0) ...[
            _avertissement(
              '$_withoutAmount embarquement${_withoutAmount > 1 ? "s" : ""} sans montant connu — '
              'le total ne ${_withoutAmount > 1 ? "les" : "le"} compte pas.',
            ),
            const SizedBox(height: 12),
          ],
          if (erreurs.isNotEmpty) ...[
            _avertissement(
              '${erreurs.length} session${erreurs.length > 1 ? "s" : ""} non lue'
              '${erreurs.length > 1 ? "s" : ""} (droits ou réseau) : le total est incomplet. '
              'Tirez pour actualiser.',
              rouge: true,
            ),
            const SizedBox(height: 12),
          ],
          Text(
            'Par $_titreRegroupement (${groupes.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          if (groupes.isEmpty && !_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Aucune session sur cette période.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...groupes.map(_groupeTile),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  /// Deux cartes côte à côte, comme l'accueil de l'app courrier : le volume
  /// à gauche, le montant à droite avec son « Détail » par gare.
  Widget _cartesResume() {
    final jour = _preset == _Preset.aujourdhui;
    final vue = _vue;
    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryBlueDark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.directions_bus_filled_outlined, color: Colors.white70),
                  const SizedBox(height: 14),
                  Text(
                    '$_boarded',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Embarquement${_boarded > 1 ? "s" : ""} · ${vue.length} session${vue.length > 1 ? "s" : ""}'
                    '${_enCours > 0 ? " ($_enCours en cours)" : ""}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.payments_outlined, color: Colors.white70),
                  const SizedBox(height: 14),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatMontant(_total),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    '${jour ? "Montant du jour" : "Montant — $_periodeCourte"}'
                    '${_enCours > 0 ? " (provisoire)" : ""}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white24,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _loading ? null : _showDetailParGare,
                      icon: const Text('Détail'),
                      label: const Icon(Icons.chevron_right, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtres() {
    final gareUnique = !widget.access.isOwner && widget.access.gares.length == 1;
    final items = <DropdownMenuItem<String?>>[
      if (widget.access.isOwner || widget.access.gares.length > 1)
        DropdownMenuItem<String?>(
          value: null,
          child: Text(widget.access.isOwner ? 'Toutes les gares' : 'Toutes mes gares'),
        ),
      ...widget.access.gares.map(
        (g) => DropdownMenuItem<String?>(value: g.id, child: Text(g.label)),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gareUnique)
            Row(
              children: [
                const Icon(Icons.location_city, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _libelleGare(widget.access.gares.first.id),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          else
            DropdownButtonFormField<String?>(
              value: _gareFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Gare',
                prefixIcon: Icon(Icons.location_city),
                isDense: true,
              ),
              items: items,
              onChanged: (v) => setState(() => _gareFilter = v),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text("Aujourd'hui"),
                selected: _preset == _Preset.aujourdhui,
                onSelected: _loading ? null : (_) => _setPreset(_Preset.aujourdhui),
              ),
              ChoiceChip(
                label: const Text('7 jours'),
                selected: _preset == _Preset.sept,
                onSelected: _loading ? null : (_) => _setPreset(_Preset.sept),
              ),
              ChoiceChip(
                label: const Text('Ce mois'),
                selected: _preset == _Preset.mois,
                onSelected: _loading ? null : (_) => _setPreset(_Preset.mois),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.date_range, size: 16),
                label: Text(_preset == _Preset.perso ? _periodeTexte : 'Période…'),
                selected: _preset == _Preset.perso,
                onSelected: _loading ? null : (_) => _setPreset(_Preset.perso),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Par gare de départ'),
                selected: _regroupement == _Regroupement.gare,
                onSelected: (_) => setState(() => _regroupement = _Regroupement.gare),
              ),
              ChoiceChip(
                label: const Text('Par itinéraire'),
                selected: _regroupement == _Regroupement.itineraire,
                onSelected: (_) => setState(() => _regroupement = _Regroupement.itineraire),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avertissement(String texte, {bool rouge = false}) {
    final couleur = rouge ? AppColors.scanInvalid : AppColors.scanDuplicate;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: rouge ? AppColors.scanInvalidBg : AppColors.scanDuplicateBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: couleur, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(texte, style: TextStyle(color: couleur, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _groupeTile(_Groupe g) {
    final dt = DateFormat('dd/MM HH:mm');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        key: PageStorageKey('${_regroupement.name}_${g.cle}'),
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryBlueLight,
          child: Icon(
            _regroupement == _Regroupement.gare ? Icons.location_city : Icons.alt_route,
            color: AppColors.primaryBlue,
            size: 18,
          ),
        ),
        title: Text(g.libelle, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${g.sessions} session${g.sessions > 1 ? "s" : ""} · '
          '${g.boarded} embarquement${g.boarded > 1 ? "s" : ""}'
          '${g.enErreur > 0 ? " · ${g.enErreur} non lue${g.enErreur > 1 ? "s" : ""}" : ""}',
        ),
        trailing: Text(
          formatMontant(g.total),
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        children: g.items.map((i) {
          final s = i.session;
          final r = i.recette;
          return ListTile(
            dense: true,
            title: Text(
              _regroupement == _Regroupement.gare ? s.routeLabel : _libelleGare(s.gareId),
            ),
            subtitle: Text(
              '${s.busLabel != null ? "Bus ${s.busLabel} · " : ""}'
              '${dt.format(s.openedAt.toLocal())} · ${s.isOpen ? "en cours" : "clôturée"}',
            ),
            trailing: r == null
                ? const Text('non lu',
                    style: TextStyle(color: AppColors.scanInvalid, fontWeight: FontWeight.bold))
                : Text(
                    formatMontant(r.total),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: r.withoutAmount > 0 ? AppColors.scanDuplicate : AppColors.textPrimary,
                    ),
                  ),
          );
        }).toList(),
      ),
    );
  }
}
