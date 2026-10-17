import 'supabase_service.dart';

/// Comptabilité (option payante « Comptabilité », module C) : dépenses de la
/// compagnie par catégorie OHADA et bilan SYSCOHADA (migration 223). Mêmes
/// RPC que la console web owner.
class ExpenseCategory {
  final String id;
  final String name;
  final String ohadaAccountCode;
  const ExpenseCategory({required this.id, required this.name, required this.ohadaAccountCode});

  String get label => '$ohadaAccountCode – $name';

  factory ExpenseCategory.fromMap(Map<String, dynamic> m) => ExpenseCategory(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        ohadaAccountCode: (m['ohadaAccountCode'] ?? '') as String,
      );
}

class CompanyExpense {
  final String id;
  final String categoryId;
  final String categoryName;
  final String ohadaAccountCode;
  final double amount;
  final DateTime expenseDate;
  final String? description;
  final String? gareName;

  const CompanyExpense({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.ohadaAccountCode,
    required this.amount,
    required this.expenseDate,
    this.description,
    this.gareName,
  });

  factory CompanyExpense.fromMap(Map<String, dynamic> m) => CompanyExpense(
        id: m['id'] as String,
        categoryId: m['categoryId'] as String,
        categoryName: (m['categoryName'] ?? '') as String,
        ohadaAccountCode: (m['ohadaAccountCode'] ?? '') as String,
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        expenseDate: DateTime.parse(m['expenseDate'] as String),
        description: m['description'] as String?,
        gareName: m['gareName'] as String?,
      );
}

class BilanLigne {
  final String? codeOhada;
  final String libelle;
  final double total;
  const BilanLigne({this.codeOhada, required this.libelle, required this.total});

  String get label => codeOhada != null && codeOhada!.isNotEmpty ? '$codeOhada – $libelle' : libelle;

  factory BilanLigne.fromMap(Map<String, dynamic> m) => BilanLigne(
        codeOhada: m['codeOhada'] as String?,
        libelle: (m['libelle'] ?? '') as String,
        total: (m['total'] as num?)?.toDouble() ?? 0,
      );
}

class BilanSyscohada {
  final String companyName;
  final DateTime from;
  final DateTime to;
  final List<BilanLigne> produits;
  final List<BilanLigne> charges;
  final double totalVentes;
  final double totalAchats;
  final double totalCharges;
  final double resultat;
  final double tresorerieCaisse;
  final double tresorerieCoffre;
  final double tresorerieBanque;

  const BilanSyscohada({
    required this.companyName,
    required this.from,
    required this.to,
    required this.produits,
    required this.charges,
    required this.totalVentes,
    required this.totalAchats,
    required this.totalCharges,
    required this.resultat,
    required this.tresorerieCaisse,
    required this.tresorerieCoffre,
    required this.tresorerieBanque,
  });

  double get tresorerieTotal => tresorerieCaisse + tresorerieCoffre + tresorerieBanque;

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  factory BilanSyscohada.fromMap(Map<String, dynamic> m) => BilanSyscohada(
        companyName: (m['companyName'] ?? '') as String,
        from: DateTime.parse(m['from'] as String),
        to: DateTime.parse(m['to'] as String),
        produits: ((m['produits'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => BilanLigne.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        charges: ((m['charges'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => BilanLigne.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        totalVentes: _d(m['totalVentes']),
        totalAchats: _d(m['totalAchats']),
        totalCharges: _d(m['totalCharges']),
        resultat: _d(m['resultat']),
        tresorerieCaisse: _d(m['tresorerieCaisse']),
        tresorerieCoffre: _d(m['tresorerieCoffre']),
        tresorerieBanque: _d(m['tresorerieBanque']),
      );
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class AccountingService {
  final _client = SupabaseService.client;

  Future<List<ExpenseCategory>> listCategories(String companyId) async {
    final data = await _client.rpc('list_company_expense_categories', params: {'p_company_id': companyId});
    return (data as List).whereType<Map>().map((m) => ExpenseCategory.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<List<CompanyExpense>> listExpenses(String companyId, DateTime from, DateTime to) async {
    final data = await _client.rpc('list_company_expenses', params: {
      'p_company_id': companyId,
      'p_from': _isoDate(from),
      'p_to': _isoDate(to),
    });
    return (data as List).whereType<Map>().map((m) => CompanyExpense.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  /// Dépense imputée à une gare (bus facultatif, migration 224).
  Future<void> saveExpense({
    required String companyId,
    String? id,
    required String categoryId,
    required double amount,
    required DateTime date,
    String? description,
    required String gareId,
  }) async {
    await _client.rpc('upsert_company_expense', params: {
      'p_company_id': companyId,
      'p_id': id,
      'p_category_id': categoryId,
      'p_amount': amount,
      'p_expense_date': _isoDate(date),
      'p_description': description,
      'p_team_member_user_id': null,
      'p_bus_id': null,
      'p_gare_id': gareId,
    });
  }

  Future<void> deleteExpense(String companyId, String id) async {
    await _client.rpc('delete_company_expense', params: {'p_company_id': companyId, 'p_id': id});
  }

  Future<BilanSyscohada> bilan(String companyId, DateTime from, DateTime to) async {
    final data = await _client.rpc('get_company_bilan', params: {
      'p_company_id': companyId,
      'p_from': _isoDate(from),
      'p_to': _isoDate(to),
    });
    return BilanSyscohada.fromMap(Map<String, dynamic>.from(data as Map));
  }
}
