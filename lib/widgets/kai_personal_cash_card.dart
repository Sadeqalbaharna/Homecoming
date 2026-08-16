import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/core/kai_cash_statement_parser.dart';

const _cashCyan = Color(0xFF2ED9FF);
const _cashAmber = Color(0xFFFFB84D);
const _cashGreen = Color(0xFF7EE787);
const _cashPanel = Color(0xFF08131D);

enum KaiCashCadence { weekly, monthly, yearly }

extension KaiCashCadenceLabel on KaiCashCadence {
  String get label => switch (this) {
        KaiCashCadence.weekly => 'weekly',
        KaiCashCadence.monthly => 'monthly',
        KaiCashCadence.yearly => 'yearly',
      };

  double monthlyValue(double amount) => switch (this) {
        KaiCashCadence.weekly => amount * 52 / 12,
        KaiCashCadence.monthly => amount,
        KaiCashCadence.yearly => amount / 12,
      };
}

class KaiCashFlowLine {
  const KaiCashFlowLine({
    required this.id,
    required this.label,
    required this.amount,
    this.cadence = KaiCashCadence.monthly,
    this.children = const [],
  });

  final String id;
  final String label;
  final double amount;
  final KaiCashCadence cadence;
  final List<KaiCashFlowLine> children;

  double get monthlyAmount => children.isEmpty
      ? cadence.monthlyValue(amount)
      : children.fold(0, (sum, item) => sum + item.monthlyAmount);

  KaiCashFlowLine copyWith({
    String? label,
    double? amount,
    KaiCashCadence? cadence,
    List<KaiCashFlowLine>? children,
  }) =>
      KaiCashFlowLine(
        id: id,
        label: label ?? this.label,
        amount: amount ?? this.amount,
        cadence: cadence ?? this.cadence,
        children: children ?? this.children,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'label': label,
        'amount': amount,
        'cadence': cadence.name,
        'children': children.map((item) => item.toJson()).toList(),
      };

  static KaiCashFlowLine? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    return KaiCashFlowLine(
      id: id,
      label: value['label']?.toString() ?? '',
      amount: (value['amount'] as num?)?.toDouble() ?? 0,
      cadence: KaiCashCadence.values.firstWhere(
        (item) => item.name == value['cadence']?.toString(),
        orElse: () => KaiCashCadence.monthly,
      ),
      children: value['children'] is List
          ? (value['children'] as List)
              .map(KaiCashFlowLine.fromJson)
              .whereType<KaiCashFlowLine>()
              .toList(growable: false)
          : const [],
    );
  }
}

class KaiCashReceivable {
  const KaiCashReceivable({
    required this.id,
    required this.source,
    required this.amount,
    required this.expectedDate,
    this.received = false,
  });

  final String id;
  final String source;
  final double amount;
  final String expectedDate;
  final bool received;

  KaiCashReceivable copyWith({
    String? source,
    double? amount,
    String? expectedDate,
    bool? received,
  }) =>
      KaiCashReceivable(
        id: id,
        source: source ?? this.source,
        amount: amount ?? this.amount,
        expectedDate: expectedDate ?? this.expectedDate,
        received: received ?? this.received,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'source': source,
        'amount': amount,
        'expectedDate': expectedDate,
        'received': received,
      };

  static KaiCashReceivable? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    return KaiCashReceivable(
      id: id,
      source: value['source']?.toString() ?? '',
      amount: (value['amount'] as num?)?.toDouble() ?? 0,
      expectedDate: value['expectedDate']?.toString() ?? '',
      received: value['received'] == true,
    );
  }
}

class KaiCashTransaction {
  const KaiCashTransaction({
    required this.id,
    required this.date,
    required this.source,
    required this.description,
    required this.category,
    required this.direction,
    required this.amount,
    this.subcategory = '',
    this.importFingerprint = '',
    this.approved = false,
  });

  final String id;
  final String date;
  final String source;
  final String description;
  final String category;
  final String subcategory;
  final KaiCashImportDirection direction;
  final double amount;
  final String importFingerprint;
  final bool approved;

  KaiCashTransaction copyWith({
    String? date,
    String? source,
    String? description,
    String? category,
    String? subcategory,
    KaiCashImportDirection? direction,
    double? amount,
    bool? approved,
  }) =>
      KaiCashTransaction(
        id: id,
        date: date ?? this.date,
        source: source ?? this.source,
        description: description ?? this.description,
        category: category ?? this.category,
        subcategory: subcategory ?? this.subcategory,
        direction: direction ?? this.direction,
        amount: amount ?? this.amount,
        importFingerprint: importFingerprint,
        approved: approved ?? this.approved,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'date': date,
        'source': source,
        'description': description,
        'category': category,
        'subcategory': subcategory,
        'direction': direction.name,
        'amount': amount,
        if (importFingerprint.isNotEmpty)
          'importFingerprint': importFingerprint,
        'approved': approved,
      };

  static KaiCashTransaction? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? '';
    final date = value['date']?.toString().trim() ?? '';
    if (id.isEmpty || date.isEmpty) return null;
    return KaiCashTransaction(
      id: id,
      date: date,
      source: value['source']?.toString() ?? '',
      description: value['description']?.toString() ?? '',
      category: value['category']?.toString() ?? 'Uncategorised',
      subcategory: value['subcategory']?.toString() ?? '',
      direction: KaiCashImportDirection.values.firstWhere(
        (item) => item.name == value['direction']?.toString(),
        orElse: () => KaiCashImportDirection.expense,
      ),
      amount: (value['amount'] as num?)?.toDouble().abs() ?? 0,
      importFingerprint: value['importFingerprint']?.toString() ?? '',
      approved: value['approved'] == true,
    );
  }
}

class KaiCashCategoryRule {
  const KaiCashCategoryRule({
    required this.merchantKey,
    required this.category,
    this.subcategory = '',
  });

  final String merchantKey;
  final String category;
  final String subcategory;

  Map<String, Object> toJson() => {
        'merchantKey': merchantKey,
        'category': category,
        'subcategory': subcategory,
      };

  static KaiCashCategoryRule? fromJson(Object? value) {
    if (value is! Map) return null;
    final merchantKey = value['merchantKey']?.toString().trim() ?? '';
    final category = value['category']?.toString().trim() ?? '';
    if (merchantKey.isEmpty || category.isEmpty) return null;
    return KaiCashCategoryRule(
      merchantKey: merchantKey,
      category: category,
      subcategory: value['subcategory']?.toString().trim() ?? '',
    );
  }
}

class KaiCashCategorySuggestion {
  const KaiCashCategorySuggestion({
    required this.category,
    required this.reason,
    this.subcategory = '',
  });

  final String category;
  final String subcategory;
  final String reason;
}

String kaiCashMerchantKey(String description) {
  var value = description.toLowerCase();
  for (final noise in const [
    'visa card pos transaction',
    'debit card switch account usd',
    'pos purchase',
    'pos pay account',
    'fawri plus payment',
    'benefit pay',
    'commission amount bhd',
  ]) {
    value = value.replaceAll(noise, ' ');
  }
  return value
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .split(' ')
      .where((token) => token.length >= 2 && !RegExp(r'^\d+$').hasMatch(token))
      .take(8)
      .join(' ')
      .trim();
}

List<KaiCashCategoryRule> kaiUpsertCashCategoryRule({
  required List<KaiCashCategoryRule> rules,
  required String description,
  required String category,
  String subcategory = '',
}) {
  final merchantKey = kaiCashMerchantKey(description);
  final cleanCategory = category.trim();
  if (merchantKey.length < 3 ||
      cleanCategory.isEmpty ||
      cleanCategory == 'Uncategorised') {
    return rules;
  }
  return [
    ...rules.where((rule) => rule.merchantKey != merchantKey),
    KaiCashCategoryRule(
      merchantKey: merchantKey,
      category: cleanCategory,
      subcategory: subcategory.trim(),
    ),
  ];
}

List<KaiCashImportCandidate> kaiApplyCashCategoryRules(
  List<KaiCashImportCandidate> candidates,
  List<KaiCashCategoryRule> rules,
) {
  final byKey = {for (final rule in rules) rule.merchantKey: rule};
  return candidates.map((candidate) {
    if (candidate.category.trim().isNotEmpty &&
        candidate.category != 'Uncategorised') {
      return candidate;
    }
    final rule = byKey[kaiCashMerchantKey(candidate.description)];
    return rule == null
        ? candidate
        : candidate.copyWith(
            category: rule.category,
            subcategory: rule.subcategory,
          );
  }).toList(growable: false);
}

KaiCashCategorySuggestion? kaiSuggestCashCategory(
  String description,
  List<KaiCashCategoryRule> rules,
) {
  final merchantKey = kaiCashMerchantKey(description);
  for (final rule in rules) {
    if (rule.merchantKey == merchantKey) {
      return KaiCashCategorySuggestion(
        category: rule.category,
        subcategory: rule.subcategory,
        reason: 'Learned merchant rule',
      );
    }
  }
  final text = description.toLowerCase();
  bool hasAny(List<String> clues) => clues.any(text.contains);
  if (hasAny(['commission amount', 'bank fee', 'service charge'])) {
    return const KaiCashCategorySuggestion(
        category: 'Bank fees', reason: 'Bank-fee wording');
  }
  if (hasAny(['internal transfer', 'fawri plus', 'benefit pay transfer'])) {
    return const KaiCashCategorySuggestion(
        category: 'Transfers', reason: 'Transfer wording');
  }
  if (hasAny(['salary', 'payroll'])) {
    return const KaiCashCategorySuggestion(
        category: 'Income', reason: 'Salary wording');
  }
  if (hasAny(['pharmacy', 'medical centre', 'hospital', 'clinic'])) {
    return const KaiCashCategorySuggestion(
        category: 'Health & pharmacy', reason: 'Health merchant wording');
  }
  if (hasAny(['supermarket', 'hypermarket', 'grocery'])) {
    return const KaiCashCategorySuggestion(
        category: 'Groceries', reason: 'Grocery merchant wording');
  }
  if (hasAny(['restaurant', 'cafe', 'coffee', 'talabat', 'deliveroo'])) {
    return const KaiCashCategorySuggestion(
        category: 'Dining', reason: 'Dining merchant wording');
  }
  if (hasAny(['netflix', 'disney+', 'spotify'])) {
    return const KaiCashCategorySuggestion(
        category: 'Subscriptions & memberships',
        reason: 'Subscription merchant');
  }
  if (hasAny(['petrol', 'fuel station', 'gas station'])) {
    return const KaiCashCategorySuggestion(
        category: 'Fuel & transport', reason: 'Fuel merchant wording');
  }
  if (hasAny(['batelco', 'stc bahrain', 'zain bahrain'])) {
    return const KaiCashCategorySuggestion(
        category: 'Telecom & utilities', reason: 'Telecom merchant wording');
  }
  if (hasAny(['rent payment', 'monthly rent'])) {
    return const KaiCashCategorySuggestion(
        category: 'Rent', reason: 'Rent wording');
  }
  if (hasAny(['insurance premium', 'insurance company'])) {
    return const KaiCashCategorySuggestion(
        category: 'Insurance', reason: 'Insurance wording');
  }
  return null;
}

List<KaiCashImportCandidate> kaiSmartAssignCashCandidates(
  List<KaiCashImportCandidate> candidates,
  List<KaiCashCategoryRule> rules,
) =>
    candidates.map((candidate) {
      if (candidate.category.trim().isNotEmpty &&
          candidate.category != 'Uncategorised') {
        return candidate;
      }
      final suggestion = kaiSuggestCashCategory(candidate.description, rules);
      return suggestion == null
          ? candidate
          : candidate.copyWith(
              category: suggestion.category,
              subcategory: suggestion.subcategory,
            );
    }).toList(growable: false);

List<KaiCashMonthRecord> kaiSmartAssignCashHistory(
  List<KaiCashMonthRecord> history,
  List<KaiCashCategoryRule> rules,
) =>
    history.map((month) {
      return month.copyWith(
        transactions: month.transactions.map((transaction) {
          if (transaction.category.trim().isNotEmpty &&
              transaction.category != 'Uncategorised') {
            return transaction;
          }
          final suggestion =
              kaiSuggestCashCategory(transaction.description, rules);
          return suggestion == null
              ? transaction
              : transaction.copyWith(
                  category: suggestion.category,
                  subcategory: suggestion.subcategory,
                  approved: true,
                );
        }).toList(growable: false),
      );
    }).toList(growable: false);

List<KaiCashMonthRecord> kaiApplyCashRulesToHistory(
  List<KaiCashMonthRecord> history,
  List<KaiCashCategoryRule> rules,
) {
  final byKey = {for (final rule in rules) rule.merchantKey: rule};
  return history.map((month) {
    return month.copyWith(
      transactions: month.transactions.map((transaction) {
        if (transaction.category.trim().isNotEmpty &&
            transaction.category != 'Uncategorised') {
          return transaction;
        }
        final rule = byKey[kaiCashMerchantKey(transaction.description)];
        return rule == null
            ? transaction
            : transaction.copyWith(
                category: rule.category,
                subcategory: rule.subcategory,
                approved: true,
              );
      }).toList(growable: false),
    );
  }).toList(growable: false);
}

enum KaiCashHistorySort {
  newest,
  oldest,
  amountHigh,
  merchant,
  category,
  account,
}

List<KaiCashTransaction> kaiSortCashTransactions(
  List<KaiCashTransaction> transactions,
  KaiCashHistorySort sort,
) {
  final result = [...transactions];
  int text(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  result.sort(switch (sort) {
    KaiCashHistorySort.newest => (a, b) => b.date.compareTo(a.date),
    KaiCashHistorySort.oldest => (a, b) => a.date.compareTo(b.date),
    KaiCashHistorySort.amountHigh => (a, b) => b.amount.compareTo(a.amount),
    KaiCashHistorySort.merchant => (a, b) => text(a.description, b.description),
    KaiCashHistorySort.category => (a, b) => text(a.category, b.category),
    KaiCashHistorySort.account => (a, b) => text(a.source, b.source),
  });
  return result;
}

class KaiCashMonthSummary {
  const KaiCashMonthSummary({
    required this.spendingByCategory,
    required this.netByAccount,
    required this.uncategorisedCount,
  });

  final Map<String, double> spendingByCategory;
  final Map<String, double> netByAccount;
  final int uncategorisedCount;
}

KaiCashMonthSummary kaiSummariseCashMonth(KaiCashMonthRecord month) {
  final categories = <String, double>{};
  final accounts = <String, double>{};
  var uncategorised = 0;
  for (final transaction in month.transactions) {
    final category = transaction.category.trim().isEmpty
        ? 'Uncategorised'
        : transaction.category.trim();
    final account = transaction.source.trim().isEmpty
        ? 'Unknown account'
        : transaction.source.trim();
    if (category == 'Uncategorised') uncategorised++;
    if (transaction.direction == KaiCashImportDirection.expense) {
      categories.update(category, (value) => value + transaction.amount,
          ifAbsent: () => transaction.amount);
      accounts.update(account, (value) => value - transaction.amount,
          ifAbsent: () => -transaction.amount);
    } else {
      accounts.update(account, (value) => value + transaction.amount,
          ifAbsent: () => transaction.amount);
    }
  }
  final sortedCategories = categories.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final sortedAccounts = accounts.entries.toList()
    ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
  return KaiCashMonthSummary(
    spendingByCategory: Map.fromEntries(sortedCategories),
    netByAccount: Map.fromEntries(sortedAccounts),
    uncategorisedCount: uncategorised,
  );
}

int kaiCashPendingApprovalCount(Iterable<KaiCashMonthRecord> history) => history
    .expand((month) => month.transactions)
    .where((transaction) => !transaction.approved)
    .length;

int kaiCashMatchingPendingCount(
  Iterable<KaiCashMonthRecord> history,
  KaiCashTransaction target,
) {
  final key = kaiCashMerchantKey(target.description);
  if (key.length < 3) return 0;
  return history
      .expand((month) => month.transactions)
      .where((transaction) =>
          !transaction.approved &&
          transaction.category == 'Uncategorised' &&
          transaction.direction == target.direction &&
          kaiCashMerchantKey(transaction.description) == key)
      .length;
}

List<KaiCashMonthRecord> kaiCategoriseMatchingCashTransactions({
  required List<KaiCashMonthRecord> history,
  required KaiCashTransaction target,
  required String category,
  String subcategory = '',
  bool approve = true,
}) {
  final key = kaiCashMerchantKey(target.description);
  if (key.length < 3 ||
      category.trim().isEmpty ||
      category == 'Uncategorised') {
    return history;
  }
  return history.map((month) {
    return month.copyWith(
      transactions: month.transactions.map((transaction) {
        final matches = !transaction.approved &&
            transaction.category == 'Uncategorised' &&
            transaction.direction == target.direction &&
            kaiCashMerchantKey(transaction.description) == key;
        return !matches
            ? transaction
            : transaction.copyWith(
                category: category.trim(),
                subcategory: subcategory.trim(),
                approved: approve,
              );
      }).toList(growable: false),
    );
  }).toList(growable: false);
}

List<KaiCashMonthRecord> kaiApproveCategorisedCashTransactions(
  List<KaiCashMonthRecord> history,
) =>
    history.map((month) {
      return month.copyWith(
        transactions: month.transactions
            .map((transaction) =>
                !transaction.approved && transaction.category != 'Uncategorised'
                    ? transaction.copyWith(approved: true)
                    : transaction)
            .toList(growable: false),
      );
    }).toList(growable: false);

class KaiCashMonthRecord {
  const KaiCashMonthRecord({
    required this.month,
    required this.income,
    required this.expenses,
    this.note = '',
    this.transactions = const [],
  });

  final String month;
  final double income;
  final double expenses;
  final String note;
  final List<KaiCashTransaction> transactions;
  double get totalIncome => transactions.isEmpty
      ? income
      : transactions
          .where((item) => item.direction == KaiCashImportDirection.income)
          .fold(0, (sum, item) => sum + item.amount);
  double get totalExpenses => transactions.isEmpty
      ? expenses
      : transactions
          .where((item) => item.direction == KaiCashImportDirection.expense)
          .fold(0, (sum, item) => sum + item.amount);
  double get cashFlow => totalIncome - totalExpenses;

  KaiCashMonthRecord copyWith({
    String? month,
    double? income,
    double? expenses,
    String? note,
    List<KaiCashTransaction>? transactions,
  }) =>
      KaiCashMonthRecord(
        month: month ?? this.month,
        income: income ?? this.income,
        expenses: expenses ?? this.expenses,
        note: note ?? this.note,
        transactions: transactions ?? this.transactions,
      );

  Map<String, Object> toJson() => {
        'month': month,
        'income': income,
        'expenses': expenses,
        'note': note,
        'transactions': transactions.map((item) => item.toJson()).toList(),
      };

  static KaiCashMonthRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final month = raw['month']?.toString().trim() ?? '';
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) return null;
    final legacyIncome = (raw['income'] as num?)?.toDouble() ?? 0;
    final legacyExpenses = (raw['expenses'] as num?)?.toDouble() ?? 0;
    final decoded = raw['transactions'] is List
        ? (raw['transactions'] as List)
            .map(KaiCashTransaction.fromJson)
            .whereType<KaiCashTransaction>()
            .toList(growable: false)
        : <KaiCashTransaction>[];
    final migrated = decoded.isNotEmpty
        ? decoded
        : <KaiCashTransaction>[
            if (legacyIncome != 0)
              KaiCashTransaction(
                id: 'legacy-income-$month',
                date: '$month-01',
                source: 'Historical summary',
                description: 'Historical income total',
                category: 'Uncategorised',
                direction: KaiCashImportDirection.income,
                amount: legacyIncome.abs(),
              ),
            if (legacyExpenses != 0)
              KaiCashTransaction(
                id: 'legacy-expense-$month',
                date: '$month-01',
                source: 'Historical summary',
                description: 'Historical spending total',
                category: 'Uncategorised',
                direction: KaiCashImportDirection.expense,
                amount: legacyExpenses.abs(),
              ),
          ];
    return KaiCashMonthRecord(
      month: month,
      income: legacyIncome,
      expenses: legacyExpenses,
      note: raw['note']?.toString() ?? '',
      transactions: migrated,
    );
  }
}

class KaiCashHistoryImportResult {
  const KaiCashHistoryImportResult({
    required this.history,
    required this.imported,
    required this.duplicates,
    required this.invalid,
  });

  final List<KaiCashMonthRecord> history;
  final int imported;
  final int duplicates;
  final int invalid;
}

KaiCashHistoryImportResult kaiMergeStatementCandidates({
  required List<KaiCashMonthRecord> history,
  required List<KaiCashImportCandidate> candidates,
  required String Function() nextId,
}) {
  final merged = [...history];
  final existingFingerprints = merged
      .expand((month) => month.transactions)
      .map((item) => item.importFingerprint)
      .where((value) => value.isNotEmpty)
      .toSet();
  var imported = 0;
  var duplicates = 0;
  var invalid = 0;
  for (final candidate in candidates.where((item) => item.selected)) {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])-([0-2]\d|3[01])$')
            .hasMatch(candidate.date) ||
        candidate.amount <= 0) {
      invalid++;
      continue;
    }
    if (!existingFingerprints.add(candidate.fingerprint)) {
      duplicates++;
      continue;
    }
    final transaction = KaiCashTransaction(
      id: nextId(),
      date: candidate.date,
      source: candidate.source,
      description: candidate.description,
      category: candidate.category,
      subcategory: candidate.subcategory,
      direction: candidate.direction,
      amount: candidate.amount,
      importFingerprint: candidate.fingerprint,
    );
    final index = merged.indexWhere((item) => item.month == candidate.month);
    if (index < 0) {
      merged.add(KaiCashMonthRecord(
        month: candidate.month,
        income: 0,
        expenses: 0,
        transactions: [transaction],
      ));
    } else {
      merged[index] = merged[index].copyWith(
        transactions: [...merged[index].transactions, transaction],
      );
    }
    imported++;
  }
  return KaiCashHistoryImportResult(
    history: merged,
    imported: imported,
    duplicates: duplicates,
    invalid: invalid,
  );
}

class KaiCashHolding {
  const KaiCashHolding({
    required this.id,
    required this.label,
    required this.value,
    this.kind = 'Investment',
  });

  final String id;
  final String label;
  final double value;
  final String kind;

  KaiCashHolding copyWith({String? label, double? value, String? kind}) =>
      KaiCashHolding(
        id: id,
        label: label ?? this.label,
        value: value ?? this.value,
        kind: kind ?? this.kind,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'label': label,
        'value': value,
        'kind': kind,
      };

  static KaiCashHolding? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    return KaiCashHolding(
      id: id,
      label: value['label']?.toString() ?? '',
      value: (value['value'] as num?)?.toDouble() ?? 0,
      kind: value['kind']?.toString() == 'Savings' ? 'Savings' : 'Investment',
    );
  }
}

class KaiCashDebt {
  const KaiCashDebt({
    required this.id,
    required this.label,
    required this.kind,
    required this.balance,
  });

  final String id;
  final String label;
  final String kind;
  final double balance;

  KaiCashDebt copyWith({String? label, String? kind, double? balance}) =>
      KaiCashDebt(
        id: id,
        label: label ?? this.label,
        kind: kind ?? this.kind,
        balance: balance ?? this.balance,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'label': label,
        'kind': kind,
        'balance': balance,
      };

  static KaiCashDebt? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    return KaiCashDebt(
      id: id,
      label: value['label']?.toString() ?? '',
      kind: value['kind']?.toString() ?? 'Debt',
      balance: (value['balance'] as num?)?.toDouble() ?? 0,
    );
  }
}

class KaiCashAccount {
  const KaiCashAccount({
    required this.id,
    required this.name,
    required this.owner,
    this.aliases = const [],
  });

  final String id;
  final String name;
  final String owner;
  final List<String> aliases;

  KaiCashAccount copyWith({
    String? name,
    String? owner,
    List<String>? aliases,
  }) =>
      KaiCashAccount(
        id: id,
        name: name ?? this.name,
        owner: owner ?? this.owner,
        aliases: aliases ?? this.aliases,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'owner': owner,
        'aliases': aliases,
      };

  static KaiCashAccount? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    return KaiCashAccount(
      id: id,
      name: value['name']?.toString() ?? '',
      owner: const {'Mine', 'Wife', 'Company', 'Other'}
              .contains(value['owner']?.toString())
          ? value['owner'].toString()
          : 'Other',
      aliases: value['aliases'] is List
          ? (value['aliases'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList(growable: false)
          : const [],
    );
  }
}

KaiCashAccount? kaiRecogniseCashAccount(
  List<KaiCashAccount> accounts,
  String evidence,
) {
  final lowerEvidence = evidence.toLowerCase();
  final matches = <(KaiCashAccount, int)>[];
  for (final account in accounts) {
    for (final alias in account.aliases) {
      final normalised = alias.trim().toLowerCase();
      if (normalised.length >= 3 && lowerEvidence.contains(normalised)) {
        matches.add((account, normalised.length));
      }
    }
  }
  if (matches.isEmpty) return null;
  matches.sort((a, b) => b.$2.compareTo(a.$2));
  return matches.first.$1;
}

List<KaiCashMonthRecord> kaiLabelCashHistoryAccounts(
  List<KaiCashMonthRecord> history,
  List<KaiCashAccount> accounts,
) =>
    history
        .map(
          (month) => month.copyWith(
            transactions: month.transactions.map((transaction) {
              final account =
                  kaiRecogniseCashAccount(accounts, transaction.source);
              if (account == null || account.name.trim().isEmpty) {
                return transaction;
              }
              return transaction.copyWith(source: account.name.trim());
            }).toList(growable: false),
          ),
        )
        .toList(growable: false);

class KaiPersonalCashSnapshot {
  const KaiPersonalCashSnapshot({
    required this.income,
    required this.expenses,
    required this.investments,
    required this.debts,
    this.cashAvailable = 0,
    this.incomeDue = 0,
    this.billsDue = 0,
    this.protectedBuffer = 0,
    this.nextIncomeDate = '',
    this.history = const [],
    this.receivables = const [],
    this.customCategories = const [],
    this.accounts = const [],
    this.categoryRules = const [],
  });

  final List<KaiCashFlowLine> income;
  final List<KaiCashFlowLine> expenses;
  final List<KaiCashHolding> investments;
  final List<KaiCashDebt> debts;
  final double cashAvailable;
  final double incomeDue;
  final double billsDue;
  final double protectedBuffer;
  final String nextIncomeDate;
  final List<KaiCashMonthRecord> history;
  final List<KaiCashReceivable> receivables;
  final List<String> customCategories;
  final List<KaiCashAccount> accounts;
  final List<KaiCashCategoryRule> categoryRules;

  static const seeded = KaiPersonalCashSnapshot(
    income: [
      KaiCashFlowLine(id: 'moon-plaza', label: 'Moon plaza', amount: 3050),
      KaiCashFlowLine(id: 'levendome', label: 'Levendome', amount: 1945),
    ],
    expenses: [
      KaiCashFlowLine(id: 'rent', label: 'Rent', amount: 850),
      KaiCashFlowLine(id: 'aira', label: 'Aira', amount: 170),
    ],
    investments: [],
    debts: [
      KaiCashDebt(
        id: 'rent-arrears',
        label: 'Rent arrears',
        kind: 'Payable',
        balance: 1275,
      ),
      KaiCashDebt(
        id: 'alsalam-cc',
        label: 'Alsalam CC',
        kind: 'Debt',
        balance: 5000,
      ),
      KaiCashDebt(
        id: 'credimax',
        label: 'Credimax',
        kind: 'Debt',
        balance: 1000,
      ),
    ],
  );

  double get monthlyIncome =>
      income.fold(0, (sum, item) => sum + item.monthlyAmount);
  double get monthlyExpenses =>
      expenses.fold(0, (sum, item) => sum + item.monthlyAmount);
  double get monthlyCashFlow => monthlyIncome - monthlyExpenses;
  double get investmentValue => investments
      .where((item) => item.kind == 'Investment')
      .fold(0, (sum, item) => sum + item.value);
  double get savingsValue => investments
      .where((item) => item.kind == 'Savings')
      .fold(0, (sum, item) => sum + item.value);
  double get savingsAndInvestmentsValue => savingsValue + investmentValue;
  double get debtBalance => debts.fold(0, (sum, item) => sum + item.balance);
  double get safeToSpend =>
      cashAvailable + incomeDue - billsDue - protectedBuffer;
  double get expenseCoverage => monthlyExpenses <= 0
      ? (monthlyIncome > 0 ? 1 : 0)
      : (monthlyIncome / monthlyExpenses).clamp(0, 1);

  KaiPersonalCashSnapshot copyWith({
    List<KaiCashFlowLine>? income,
    List<KaiCashFlowLine>? expenses,
    List<KaiCashHolding>? investments,
    List<KaiCashDebt>? debts,
    double? cashAvailable,
    double? incomeDue,
    double? billsDue,
    double? protectedBuffer,
    String? nextIncomeDate,
    List<KaiCashMonthRecord>? history,
    List<KaiCashReceivable>? receivables,
    List<String>? customCategories,
    List<KaiCashAccount>? accounts,
    List<KaiCashCategoryRule>? categoryRules,
  }) =>
      KaiPersonalCashSnapshot(
        income: income ?? this.income,
        expenses: expenses ?? this.expenses,
        investments: investments ?? this.investments,
        debts: debts ?? this.debts,
        cashAvailable: cashAvailable ?? this.cashAvailable,
        incomeDue: incomeDue ?? this.incomeDue,
        billsDue: billsDue ?? this.billsDue,
        protectedBuffer: protectedBuffer ?? this.protectedBuffer,
        nextIncomeDate: nextIncomeDate ?? this.nextIncomeDate,
        history: history ?? this.history,
        receivables: receivables ?? this.receivables,
        customCategories: customCategories ?? this.customCategories,
        accounts: accounts ?? this.accounts,
        categoryRules: categoryRules ?? this.categoryRules,
      );

  Map<String, Object> toJson() => {
        'version': 6,
        'income': income.map((item) => item.toJson()).toList(),
        'expenses': expenses.map((item) => item.toJson()).toList(),
        'investments': investments.map((item) => item.toJson()).toList(),
        'debts': debts.map((item) => item.toJson()).toList(),
        'cashAvailable': cashAvailable,
        'incomeDue': incomeDue,
        'billsDue': billsDue,
        'protectedBuffer': protectedBuffer,
        'nextIncomeDate': nextIncomeDate,
        'history': history.map((item) => item.toJson()).toList(),
        'receivables': receivables.map((item) => item.toJson()).toList(),
        'customCategories': customCategories,
        'accounts': accounts.map((item) => item.toJson()).toList(),
        'categoryRules': categoryRules.map((item) => item.toJson()).toList(),
      };

  static KaiPersonalCashSnapshot? fromJson(Object? value) {
    if (value is! Map ||
        (value['version'] != 1 &&
            value['version'] != 2 &&
            value['version'] != 3 &&
            value['version'] != 4 &&
            value['version'] != 5 &&
            value['version'] != 6)) {
      return null;
    }
    List<T> decode<T>(Object? raw, T? Function(Object?) parser) => raw is List
        ? raw.map(parser).whereType<T>().toList(growable: false)
        : <T>[];

    return KaiPersonalCashSnapshot(
      income: decode(value['income'], KaiCashFlowLine.fromJson),
      expenses: decode(value['expenses'], KaiCashFlowLine.fromJson),
      investments: decode(value['investments'], KaiCashHolding.fromJson),
      debts: decode(value['debts'], KaiCashDebt.fromJson),
      cashAvailable: (value['cashAvailable'] as num?)?.toDouble() ?? 0,
      incomeDue: (value['incomeDue'] as num?)?.toDouble() ?? 0,
      billsDue: (value['billsDue'] as num?)?.toDouble() ?? 0,
      protectedBuffer: (value['protectedBuffer'] as num?)?.toDouble() ?? 0,
      nextIncomeDate: value['nextIncomeDate']?.toString() ?? '',
      history: decode(value['history'], KaiCashMonthRecord.fromJson),
      receivables: decode(value['receivables'], KaiCashReceivable.fromJson),
      customCategories: value['customCategories'] is List
          ? (value['customCategories'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList(growable: false)
          : const [],
      accounts: decode(value['accounts'], KaiCashAccount.fromJson),
      categoryRules:
          decode(value['categoryRules'], KaiCashCategoryRule.fromJson),
    );
  }
}

class KaiPersonalCashStore {
  KaiPersonalCashStore._();
  static final instance = KaiPersonalCashStore._();
  static const _key = 'kai_personal_cash_snapshot_v1';
  Future<void> _writeTail = Future<void>.value();

  Future<KaiPersonalCashSnapshot> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return KaiPersonalCashSnapshot.seeded;
    try {
      return KaiPersonalCashSnapshot.fromJson(jsonDecode(raw)) ??
          KaiPersonalCashSnapshot.seeded;
    } catch (_) {
      return KaiPersonalCashSnapshot.seeded;
    }
  }

  Future<void> save(KaiPersonalCashSnapshot snapshot) {
    final payload = jsonEncode(snapshot.toJson());
    _writeTail = _writeTail.then((_) async {
      await (await SharedPreferences.getInstance()).setString(_key, payload);
    });
    return _writeTail;
  }
}

class KaiPersonalCashCard extends StatefulWidget {
  const KaiPersonalCashCard({super.key});

  @override
  State<KaiPersonalCashCard> createState() => _KaiPersonalCashCardState();
}

class _KaiPersonalCashCardState extends State<KaiPersonalCashCard> {
  KaiPersonalCashSnapshot _snapshot = KaiPersonalCashSnapshot.seeded;

  @override
  void initState() {
    super.initState();
    KaiPersonalCashStore.instance.load().then((value) {
      if (mounted) setState(() => _snapshot = value);
    });
  }

  Future<void> _open() async {
    final updated = await showDialog<KaiPersonalCashSnapshot>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.78),
      builder: (_) => _KaiPersonalCashDialog(initial: _snapshot),
    );
    if (mounted && updated != null) setState(() => _snapshot = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('personal-cash-card'),
        onTap: _open,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _cashPanel.withOpacity(0.94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cashCyan.withOpacity(0.38)),
            boxShadow: [
              BoxShadow(
                color: _cashCyan.withOpacity(0.07),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      color: _cashCyan, size: 17),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'PERSONAL CASH',
                      style: TextStyle(
                        color: Color(0xFFDCEAF4),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Text(
                    'EXPAND',
                    style: TextStyle(
                      color: _cashCyan,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      fontFamily: 'monospace',
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.open_in_full, color: _cashCyan, size: 13),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _CompactCashMetric(
                    label: 'INCOME',
                    value: 'BD ${_money(_snapshot.monthlyIncome)}',
                    color: _cashGreen,
                  ),
                  _CompactCashMetric(
                    label: 'EXPENSES',
                    value: 'BD ${_money(_snapshot.monthlyExpenses)}',
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _CompactCashMetric(
                    label: 'MONTHLY FLOW',
                    value: 'BD ${_signedMoney(_snapshot.monthlyCashFlow)}',
                    color: _snapshot.monthlyCashFlow >= 0
                        ? _cashGreen
                        : const Color(0xFFFF6B6B),
                  ),
                  _CompactCashMetric(
                    label: 'DEBT',
                    value: 'BD ${_money(_snapshot.debtBalance)}',
                    color: _cashAmber,
                  ),
                ],
              ),
              const SizedBox(height: 9),
              LinearProgressIndicator(
                value: _snapshot.expenseCoverage,
                minHeight: 5,
                color: _cashGreen,
                backgroundColor: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 6),
              const Text(
                'LOCAL ONLY · click for the full breakdown',
                style: TextStyle(
                  color: Color(0xFF7F94A5),
                  fontSize: 8,
                  letterSpacing: 0.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wide-screen home for the same local cash snapshot used by the compact card.
/// It deliberately stays read-only until EDIT is selected, so the dashboard can
/// show the useful breakdown without turning the whole rail into a form.
class KaiPersonalCashDock extends StatefulWidget {
  const KaiPersonalCashDock({super.key});

  @override
  State<KaiPersonalCashDock> createState() => _KaiPersonalCashDockState();
}

class _KaiPersonalCashDockState extends State<KaiPersonalCashDock> {
  KaiPersonalCashSnapshot _snapshot = KaiPersonalCashSnapshot.seeded;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    KaiPersonalCashStore.instance.load().then((value) {
      if (mounted) setState(() => _snapshot = value);
    });
  }

  Future<void> _edit() async {
    final updated = await showDialog<KaiPersonalCashSnapshot>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.78),
      builder: (_) => _KaiPersonalCashDialog(initial: _snapshot),
    );
    if (mounted && updated != null) setState(() => _snapshot = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('personal-cash-dock'),
      decoration: BoxDecoration(
        color: _cashPanel.withOpacity(0.91),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cashCyan.withOpacity(0.38)),
        boxShadow: [
          BoxShadow(color: _cashCyan.withOpacity(0.06), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dockHeader(),
          if (_expanded)
            Expanded(
              child: ListView(
                key: const Key('personal-cash-dock-scroll'),
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                children: [
                  _dockSummary(),
                  const SizedBox(height: 14),
                  _dockTiming(),
                  const SizedBox(height: 14),
                  _dockLines(
                    title: 'INCOME SOURCES',
                    icon: Icons.paid_outlined,
                    color: _cashGreen,
                    rows: _snapshot.income
                        .map((item) => MapEntry(
                            item.label, 'BD ${_money(item.monthlyAmount)}/mo'))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  _dockLines(
                    title: 'EXPENSE CATEGORIES',
                    icon: Icons.receipt_long_outlined,
                    color: const Color(0xFFDCEAF4),
                    rows: _snapshot.expenses
                        .map((item) => MapEntry(
                            item.label, 'BD ${_money(item.monthlyAmount)}/mo'))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  _dockLines(
                    title: 'INVESTMENTS',
                    icon: Icons.candlestick_chart_outlined,
                    color: _cashCyan,
                    rows: _snapshot.investments
                        .map((item) =>
                            MapEntry(item.label, 'BD ${_money(item.value)}'))
                        .toList(),
                    empty: 'No holdings recorded',
                  ),
                  const SizedBox(height: 12),
                  _dockLines(
                    title: 'DEBTS + PAYABLES',
                    icon: Icons.account_balance_outlined,
                    color: _cashAmber,
                    rows: _snapshot.debts
                        .map((item) => MapEntry(item.label,
                            '${item.kind}  ·  BD ${_money(item.balance)}'))
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'LOCAL ONLY  ·  saved on this desktop  ·  no Firebase',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6F8798),
                      fontSize: 8,
                      letterSpacing: 0.55,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _dockSummary(),
            ),
        ],
      ),
    );
  }

  Widget _dockHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                color: _cashCyan, size: 18),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'PERSONAL CASH',
                style: TextStyle(
                  color: Color(0xFFDCEAF4),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            TextButton(
              key: const Key('personal-cash-dock-edit'),
              onPressed: _edit,
              child: const Text('EDIT',
                  style: TextStyle(
                      color: _cashCyan,
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ),
            IconButton(
              key: const Key('personal-cash-dock-toggle'),
              tooltip:
                  _expanded ? 'Collapse personal cash' : 'Expand personal cash',
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.unfold_less : Icons.unfold_more,
                color: const Color(0xFF8EA7B8),
                size: 19,
              ),
            ),
          ],
        ),
      );

  Widget _dockSummary() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1A26).withOpacity(0.88),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _cashCyan.withOpacity(0.16)),
        ),
        child: Column(
          children: [
            Row(children: [
              _CompactCashMetric(
                  label: 'INCOME',
                  value: 'BD ${_money(_snapshot.monthlyIncome)}',
                  color: _cashGreen),
              _CompactCashMetric(
                  label: 'EXPENSES',
                  value: 'BD ${_money(_snapshot.monthlyExpenses)}',
                  color: const Color(0xFFDCEAF4)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _CompactCashMetric(
                  label: 'MONTHLY FLOW',
                  value: 'BD ${_signedMoney(_snapshot.monthlyCashFlow)}',
                  color: _snapshot.monthlyCashFlow >= 0
                      ? _cashGreen
                      : const Color(0xFFFF6B6B)),
              _CompactCashMetric(
                  label: 'DEBT',
                  value: 'BD ${_money(_snapshot.debtBalance)}',
                  color: _cashAmber),
            ]),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _snapshot.expenseCoverage,
              minHeight: 4,
              color: _cashGreen,
              backgroundColor: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
            ),
          ],
        ),
      );

  Widget _dockTiming() => Row(
        children: [
          _dockMiniMetric(
              'SAFE TO SPEND', 'BD ${_signedMoney(_snapshot.safeToSpend)}'),
          const SizedBox(width: 8),
          _dockMiniMetric(
              'NEXT INCOME',
              _snapshot.nextIncomeDate.isEmpty
                  ? 'Not set'
                  : _snapshot.nextIncomeDate),
        ],
      );

  Widget _dockMiniMetric(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.025),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF71899A),
                    fontSize: 7.5,
                    letterSpacing: 0.6,
                    fontFamily: 'monospace')),
            const SizedBox(height: 3),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFFDCEAF4),
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _dockLines({
    required String title,
    required IconData icon,
    required Color color,
    required List<MapEntry<String, String>> rows,
    String empty = 'Nothing recorded',
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.018),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withOpacity(0.065)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 7),
              Text(title,
                  style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.75,
                      fontFamily: 'monospace')),
            ]),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Text(empty,
                  style:
                      const TextStyle(color: Color(0xFF71899A), fontSize: 10))
            else
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(
                        child: Text(row.key,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFFB8CBD8), fontSize: 10.5))),
                    const SizedBox(width: 8),
                    Text(row.value,
                        style: const TextStyle(
                            color: Color(0xFFDCEAF4),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
          ],
        ),
      );
}

class _CompactCashMetric extends StatelessWidget {
  const _CompactCashMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF7F94A5),
                    fontSize: 7.5,
                    letterSpacing: 0.6,
                    fontFamily: 'monospace')),
          ],
        ),
      );
}

class _KaiPersonalCashDialog extends StatefulWidget {
  const _KaiPersonalCashDialog({required this.initial});
  final KaiPersonalCashSnapshot initial;

  @override
  State<_KaiPersonalCashDialog> createState() => _KaiPersonalCashDialogState();
}

class _KaiPersonalCashDialogState extends State<_KaiPersonalCashDialog> {
  late KaiPersonalCashSnapshot _value = widget.initial;
  int _sequence = 0;
  int _activeTab = 0;
  List<KaiCashImportCandidate> _importCandidates = const [];
  String _importStatus = 'No statement selected.';
  bool _importBusy = false;
  KaiCashHistorySort _historySort = KaiCashHistorySort.newest;
  bool _historyOnlyUncategorised = false;
  bool _historyShowApproved = false;
  final Map<String, TextEditingController> _accountSourceControllers = {};

  @override
  void dispose() {
    for (final controller in _accountSourceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _update(KaiPersonalCashSnapshot next) {
    setState(() => _value = next);
    unawaited(KaiPersonalCashStore.instance.save(next));
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  List<String> _categoryOptions([String current = '']) {
    final values = <String>{
      'Uncategorised',
      'Income',
      ..._value.expenses.map((item) => item.label.trim()),
      ..._value.customCategories.map((item) => item.trim()),
      ..._value.history.expand(
        (month) => month.transactions.map((item) => item.category.trim()),
      ),
      ..._importCandidates.map((item) => item.category.trim()),
      current.trim(),
    }..removeWhere((item) => item.isEmpty);
    final sorted = values.toList()..sort((a, b) => a.compareTo(b));
    return sorted;
  }

  Future<String?> _addCategory() async {
    var draft = '';
    final category = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF101813),
        title: const Text('Add category'),
        content: TextField(
          key: const Key('cash-new-category-name'),
          autofocus: true,
          style: _inputStyle,
          decoration: _inputDecoration('Category name'),
          onChanged: (value) => draft = value,
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.of(context).pop(trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('cash-save-new-category'),
            onPressed: () {
              final trimmed = draft.trim();
              if (trimmed.isNotEmpty) Navigator.of(context).pop(trimmed);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (category == null || category.trim().isEmpty || !mounted) return null;
    final trimmed = category.trim();
    final categories = <String>{..._value.customCategories, trimmed}.toList()
      ..sort((a, b) => a.compareTo(b));
    _update(_value.copyWith(customCategories: categories));
    return trimmed;
  }

  Widget _categoryPicker({
    required String value,
    required ValueChanged<String> onChanged,
    required String keyPrefix,
  }) {
    final options = _categoryOptions(value);
    return DropdownButtonFormField<String>(
      key: Key('$keyPrefix-category'),
      value: value.trim().isEmpty ? 'Uncategorised' : value.trim(),
      isExpanded: true,
      dropdownColor: const Color(0xFF18221C),
      decoration: _inputDecoration('Category'),
      style: _inputStyle,
      items: options
          .map((category) => DropdownMenuItem(
                value: category,
                child: Text(category, overflow: TextOverflow.ellipsis),
              ))
          .toList(growable: false),
      onChanged: (category) {
        if (category != null) onChanged(category);
      },
    );
  }

  Widget _accountSourceEditor({
    required String value,
    required ValueChanged<String> onChanged,
    required String keyPrefix,
  }) {
    final controller = _accountSourceControllers.putIfAbsent(
      keyPrefix,
      () => TextEditingController(text: value),
    );
    if (controller.text != value) {
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    final accounts = _value.accounts
        .where((account) => account.name.trim().isNotEmpty)
        .toList(growable: false);
    return Row(children: [
      Expanded(
        child: TextFormField(
          key: Key('$keyPrefix-source'),
          controller: controller,
          onChanged: onChanged,
          style: _inputStyle,
          decoration: _inputDecoration('Source / account'),
        ),
      ),
      const SizedBox(width: 5),
      PopupMenuButton<String>(
        key: Key('$keyPrefix-account-picker'),
        enabled: accounts.isNotEmpty,
        tooltip: accounts.isEmpty
            ? 'Add a recognised account first'
            : 'Choose a recognised account',
        color: const Color(0xFF18221C),
        icon: Icon(
          Icons.account_balance_wallet_outlined,
          size: 17,
          color: accounts.isEmpty ? Colors.white24 : _cashCyan,
        ),
        itemBuilder: (context) => accounts
            .map(
              (account) => PopupMenuItem<String>(
                value: account.name,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.name, style: _inputStyle),
                    Text(
                      account.owner,
                      style: const TextStyle(
                        color: Color(0xFF7F94A5),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
        onSelected: (accountName) {
          controller.value = TextEditingValue(
            text: accountName,
            selection: TextSelection.collapsed(offset: accountName.length),
          );
          onChanged(accountName);
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 860),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF101813),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cashAmber.withOpacity(0.55)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.65),
                blurRadius: 34,
              ),
            ],
          ),
          child: Column(
            children: [
              _header(),
              _cashTabs(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _activeContent(),
                      const SizedBox(height: 14),
                      const Row(
                        children: [
                          Icon(Icons.lock_outline,
                              color: Color(0xFF7F94A5), size: 13),
                          SizedBox(width: 6),
                          Text(
                            'Saves locally on this computer. Statements are reviewed locally; No Firebase or bank connection.',
                            style: TextStyle(
                                color: Color(0xFF7F94A5), fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cashTabs() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            for (final entry in const [
              (0, 'Overview', Icons.dashboard_outlined),
              (1, 'Receivables', Icons.event_available_outlined),
              (2, 'History', Icons.receipt_long_outlined),
              (3, 'Import statement', Icons.upload_file_outlined),
              (4, 'Accounts', Icons.account_balance_outlined),
            ]) ...[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: OutlinedButton.icon(
                    key: Key('cash-tab-${entry.$1}'),
                    onPressed: () => setState(() => _activeTab = entry.$1),
                    icon: Icon(entry.$3, size: 15),
                    label: Text(entry.$2),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          _activeTab == entry.$1 ? _cashCyan : Colors.white70,
                      backgroundColor: _activeTab == entry.$1
                          ? _cashCyan.withOpacity(.09)
                          : Colors.transparent,
                      side: BorderSide(
                        color: _activeTab == entry.$1
                            ? _cashCyan.withOpacity(.7)
                            : Colors.white.withOpacity(.12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _activeContent() => switch (_activeTab) {
        1 => _receivablesSection(),
        2 => _historySection(),
        3 => _statementImportSection(),
        4 => _accountsSection(),
        _ => _overviewContent(),
      };

  Widget _overviewContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summary(),
          const SizedBox(height: 16),
          _timingFields(),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final income = _flowSection(
              title: 'Income sources',
              icon: Icons.paid_outlined,
              total: _value.monthlyIncome,
              items: _value.income,
              onChange: (items) => _update(_value.copyWith(income: items)),
              addLabel: 'Add income source',
              addPrefix: 'income',
            );
            final expenses = _flowSection(
              title: 'Expense categories',
              icon: Icons.receipt_long_outlined,
              total: _value.monthlyExpenses,
              items: _value.expenses,
              onChange: (items) => _update(_value.copyWith(expenses: items)),
              addLabel: 'Add expense category',
              addPrefix: 'expense',
              allowChildren: true,
            );
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: income),
                    const SizedBox(width: 20),
                    Expanded(child: expenses),
                  ])
                : Column(children: [income, expenses]);
          }),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _holdingSection()),
                    const SizedBox(width: 20),
                    Expanded(child: _debtSection()),
                  ])
                : Column(children: [_holdingSection(), _debtSection()]);
          }),
        ],
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet_outlined,
                color: _cashAmber, size: 23),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Personal cash breakdown',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  Text('PRIVATE · LOCAL DESKTOP SNAPSHOT',
                      style: TextStyle(
                          color: _cashCyan,
                          fontSize: 8,
                          letterSpacing: 1.0,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
            TextButton.icon(
              key: const Key('personal-cash-close'),
              onPressed: () => Navigator.of(context).pop(_value),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Close'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ],
        ),
      );

  Widget _summary() => Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryMetric('MONTHLY INCOME', _value.monthlyIncome,
                  color: _cashGreen),
              _SummaryMetric('MONTHLY EXPENSES', _value.monthlyExpenses),
              _SummaryMetric('MONTHLY CASH FLOW', _value.monthlyCashFlow,
                  signed: true,
                  color: _value.monthlyCashFlow >= 0
                      ? _cashGreen
                      : const Color(0xFFFF6B6B)),
              _SummaryMetric(
                  'SAVINGS + INVESTMENTS', _value.savingsAndInvestmentsValue),
              _SummaryMetric('DEBTS + PAYABLES', _value.debtBalance,
                  color: _cashAmber),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _bar(
                  'Income covers monthly expenses',
                  _value.expenseCoverage,
                  '${(_value.expenseCoverage * 100).round()}%',
                  _cashGreen,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _bar(
                  'Debt versus savings + investments',
                  _value.debtBalance <= 0
                      ? 1
                      : (_value.savingsAndInvestmentsValue / _value.debtBalance)
                          .clamp(0, 1),
                  'BD ${_signedMoney(_value.savingsAndInvestmentsValue - _value.debtBalance)}',
                  _cashAmber,
                ),
              ),
            ],
          ),
        ],
      );

  Widget _bar(String label, double value, String trailing, Color color) =>
      Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: _smallStyle)),
              Text(trailing,
                  style: _smallStyle.copyWith(
                      color: color, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(
            value: value,
            minHeight: 7,
            color: color,
            backgroundColor: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
        ],
      );

  Widget _timingFields() => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _numberField('Cash available now', _value.cashAvailable,
              (v) => _update(_value.copyWith(cashAvailable: v))),
          _numberField('Income due before then', _value.incomeDue,
              (v) => _update(_value.copyWith(incomeDue: v))),
          _numberField('Bills due before then', _value.billsDue,
              (v) => _update(_value.copyWith(billsDue: v))),
          _numberField('Protected buffer', _value.protectedBuffer,
              (v) => _update(_value.copyWith(protectedBuffer: v))),
          SizedBox(
            width: 180,
            child: _labelledField(
              'Next income date',
              TextFormField(
                initialValue: _value.nextIncomeDate,
                onChanged: (v) =>
                    _update(_value.copyWith(nextIncomeDate: v.trim())),
                style: _inputStyle,
                decoration: _inputDecoration('mm/dd/yyyy'),
              ),
            ),
          ),
          Container(
            width: 180,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _value.safeToSpend >= 0
                  ? _cashGreen.withOpacity(0.08)
                  : const Color(0xFFFF6B6B).withOpacity(0.08),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: (_value.safeToSpend >= 0
                        ? _cashGreen
                        : const Color(0xFFFF6B6B))
                    .withOpacity(0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SAFE TO SPEND', style: _tinyStyle),
                Text('BD ${_signedMoney(_value.safeToSpend)}',
                    style: TextStyle(
                        color: _value.safeToSpend >= 0
                            ? _cashGreen
                            : const Color(0xFFFF6B6B),
                        fontWeight: FontWeight.w900,
                        fontSize: 15)),
              ],
            ),
          ),
        ],
      );

  Widget _numberField(
          String label, double value, ValueChanged<double> onValue) =>
      SizedBox(
        width: 180,
        child: _labelledField(
          label,
          TextFormField(
            initialValue: _editableNumber(value),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) => onValue(double.tryParse(v) ?? 0),
            style: _inputStyle,
            decoration: _inputDecoration('0'),
          ),
        ),
      );

  Widget _flowSection({
    required String title,
    required IconData icon,
    required double total,
    required List<KaiCashFlowLine> items,
    required ValueChanged<List<KaiCashFlowLine>> onChange,
    required String addLabel,
    required String addPrefix,
    bool allowChildren = false,
  }) {
    return _section(
      title: title,
      icon: icon,
      total: total,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _flowRow(items, i, onChange, allowChildren: allowChildren),
          const SizedBox(height: 7),
        ],
        _addButton(addLabel, () {
          onChange([
            ...items,
            KaiCashFlowLine(id: _id(addPrefix), label: '', amount: 0),
          ]);
        }),
      ],
    );
  }

  Widget _flowRow(
    List<KaiCashFlowLine> items,
    int index,
    ValueChanged<List<KaiCashFlowLine>> onChange, {
    bool allowChildren = false,
  }) {
    final item = items[index];
    void replace(KaiCashFlowLine next) {
      final copy = [...items]..[index] = next;
      onChange(copy);
    }

    final row = Row(children: [
      Expanded(
        flex: 4,
        child: TextFormField(
          initialValue: item.label,
          onChanged: (v) => replace(item.copyWith(label: v)),
          style: _inputStyle,
          decoration: _inputDecoration('Name'),
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        flex: 2,
        child: TextFormField(
          initialValue: _editableNumber(item.amount),
          onChanged: (v) =>
              replace(item.copyWith(amount: double.tryParse(v) ?? 0)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: _inputStyle,
          decoration: _inputDecoration('0'),
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        flex: 3,
        child: DropdownButtonFormField<KaiCashCadence>(
          value: item.cadence,
          isExpanded: true,
          dropdownColor: const Color(0xFF18221C),
          decoration: _inputDecoration(''),
          style: _inputStyle,
          items: KaiCashCadence.values
              .map((value) =>
                  DropdownMenuItem(value: value, child: Text(value.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) replace(item.copyWith(cadence: v));
          },
        ),
      ),
      IconButton(
        tooltip: 'Remove',
        onPressed: () => onChange([...items]..removeAt(index)),
        icon: const Icon(Icons.close, size: 15, color: Color(0xFF9FB6C8)),
      ),
      if (allowChildren)
        IconButton(
          key: Key('cash-add-subcategory-${item.id}'),
          tooltip: 'Add subcategory',
          onPressed: () => replace(item.copyWith(children: [
            ...item.children,
            KaiCashFlowLine(id: _id('expense-child'), label: '', amount: 0),
          ])),
          icon: const Icon(Icons.account_tree_outlined,
              size: 16, color: _cashCyan),
        ),
    ]);
    if (!allowChildren || item.children.isEmpty) return row;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row,
      const SizedBox(height: 7),
      Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Column(children: [
          for (var childIndex = 0;
              childIndex < item.children.length;
              childIndex++) ...[
            _subcategoryRow(item, childIndex, replace),
            const SizedBox(height: 6),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Category total  BD ${_money(item.monthlyAmount)} / mo',
              style: const TextStyle(
                  color: _cashAmber, fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _subcategoryRow(KaiCashFlowLine parent, int index,
      ValueChanged<KaiCashFlowLine> replaceParent) {
    final child = parent.children[index];
    void replaceChild(KaiCashFlowLine next) {
      final children = [...parent.children]..[index] = next;
      replaceParent(parent.copyWith(children: children));
    }

    return Row(children: [
      const Icon(Icons.subdirectory_arrow_right,
          size: 15, color: Color(0xFF71899A)),
      const SizedBox(width: 6),
      Expanded(
        flex: 4,
        child: TextFormField(
          key: Key('cash-subcategory-label-${child.id}'),
          initialValue: child.label,
          onChanged: (v) => replaceChild(child.copyWith(label: v)),
          style: _inputStyle,
          decoration: _inputDecoration('Subcategory, e.g. Netflix'),
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        flex: 2,
        child: TextFormField(
          key: Key('cash-subcategory-amount-${child.id}'),
          initialValue: _editableNumber(child.amount),
          onChanged: (v) =>
              replaceChild(child.copyWith(amount: double.tryParse(v) ?? 0)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: _inputStyle,
          decoration: _inputDecoration('0'),
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        flex: 3,
        child: DropdownButtonFormField<KaiCashCadence>(
          value: child.cadence,
          isExpanded: true,
          dropdownColor: const Color(0xFF18221C),
          decoration: _inputDecoration(''),
          style: _inputStyle,
          items: KaiCashCadence.values
              .map((value) =>
                  DropdownMenuItem(value: value, child: Text(value.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) replaceChild(child.copyWith(cadence: v));
          },
        ),
      ),
      IconButton(
        tooltip: 'Remove subcategory',
        onPressed: () {
          final children = [...parent.children]..removeAt(index);
          replaceParent(parent.copyWith(children: children));
        },
        icon: const Icon(Icons.close, size: 15, color: Color(0xFF9FB6C8)),
      ),
    ]);
  }

  Widget _receivablesSection() {
    final outstanding = _value.receivables
        .where((item) => !item.received)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final ordered = [..._value.receivables]
      ..sort((a, b) => a.expectedDate.compareTo(b.expectedDate));
    return _section(
      title: 'Expected receivables',
      icon: Icons.event_available_outlined,
      total: outstanding,
      children: [
        const Text(
          'Track money expected but not yet received. Marking an item received closes the expectation; it does not invent bank evidence or alter the live budget.',
          style: TextStyle(color: Color(0xFF9FB6C8), fontSize: 10),
        ),
        const SizedBox(height: 12),
        for (final item in ordered) ...[
          _receivableRow(item),
          const SizedBox(height: 8),
        ],
        _addButton('Add receivable', () {
          _update(_value.copyWith(receivables: [
            ..._value.receivables,
            KaiCashReceivable(
              id: _id('receivable'),
              source: '',
              amount: 0,
              expectedDate: '',
            ),
          ]));
        }),
      ],
    );
  }

  Widget _receivableRow(KaiCashReceivable item) {
    void replace(KaiCashReceivable next) {
      final values = _value.receivables
          .map((value) => identical(value, item) ? next : value)
          .toList(growable: false);
      _update(_value.copyWith(receivables: values));
    }

    return Container(
      key: Key('cash-receivable-${item.id}'),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.025),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: item.received
              ? _cashGreen.withOpacity(.28)
              : Colors.white.withOpacity(.08),
        ),
      ),
      child: Row(children: [
        Checkbox(
          value: item.received,
          onChanged: (value) =>
              replace(item.copyWith(received: value ?? false)),
          activeColor: _cashGreen,
        ),
        Expanded(
          flex: 4,
          child: TextFormField(
            initialValue: item.source,
            onChanged: (value) => replace(item.copyWith(source: value)),
            style: _inputStyle,
            decoration: _inputDecoration('Source'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: _editableNumber(item.amount),
            onChanged: (value) =>
                replace(item.copyWith(amount: double.tryParse(value) ?? 0)),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: _inputStyle,
            decoration: _inputDecoration('Amount'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextFormField(
            initialValue: item.expectedDate,
            onChanged: (value) =>
                replace(item.copyWith(expectedDate: value.trim())),
            style: _inputStyle,
            decoration: _inputDecoration('Expected YYYY-MM-DD'),
          ),
        ),
        IconButton(
          tooltip: 'Remove receivable',
          onPressed: () => _update(_value.copyWith(
            receivables: _value.receivables
                .where((value) => !identical(value, item))
                .toList(growable: false),
          )),
          icon: const Icon(Icons.delete_outline,
              size: 17, color: Color(0xFFFF6B6B)),
        ),
      ]),
    );
  }

  Widget _historySection() {
    final sorted = [..._value.history]
      ..sort((a, b) => a.month.compareTo(b.month));
    final pendingApproval = kaiCashPendingApprovalCount(sorted);
    return _section(
      title: 'Monthly history + patterns',
      icon: Icons.insights_outlined,
      total: sorted.isEmpty ? 0 : sorted.last.cashFlow,
      children: [
        const Text(
          'Enter completed months to compare income and spending. This history does not alter the live budget above.',
          style: TextStyle(color: Color(0xFF9FB6C8), fontSize: 10),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const Key('cash-history-add-category'),
              onPressed: _addCategory,
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('Add reusable category'),
            ),
            PopupMenuButton<KaiCashHistorySort>(
              key: const Key('cash-history-sort'),
              tooltip: 'Sort transactions',
              color: const Color(0xFF18221C),
              initialValue: _historySort,
              onSelected: (value) => setState(() => _historySort = value),
              itemBuilder: (context) => const {
                KaiCashHistorySort.newest: 'Newest first',
                KaiCashHistorySort.oldest: 'Oldest first',
                KaiCashHistorySort.amountHigh: 'Largest amount',
                KaiCashHistorySort.merchant: 'Merchant A-Z',
                KaiCashHistorySort.category: 'Category A-Z',
                KaiCashHistorySort.account: 'Account A-Z',
              }
                  .entries
                  .map((entry) => PopupMenuItem(
                        value: entry.key,
                        child: Row(children: [
                          SizedBox(
                            width: 22,
                            child: entry.key == _historySort
                                ? const Icon(Icons.check,
                                    size: 16, color: _cashCyan)
                                : null,
                          ),
                          Text(entry.value, style: _inputStyle),
                        ]),
                      ))
                  .toList(growable: false),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF18221C),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(.16)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.sort, size: 17, color: _cashCyan),
                  const SizedBox(width: 8),
                  const Text('SORT',
                      style: TextStyle(
                          color: _cashCyan,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8)),
                  const SizedBox(width: 8),
                  Text(
                    const {
                      KaiCashHistorySort.newest: 'Newest',
                      KaiCashHistorySort.oldest: 'Oldest',
                      KaiCashHistorySort.amountHigh: 'Largest',
                      KaiCashHistorySort.merchant: 'Merchant',
                      KaiCashHistorySort.category: 'Category',
                      KaiCashHistorySort.account: 'Account',
                    }[_historySort]!,
                    style: _inputStyle,
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.arrow_drop_down,
                      size: 18, color: Colors.white70),
                ]),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('cash-smart-category-assign'),
              onPressed: _smartAssignHistory,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('SMART CATEGORY ASSIGN'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _cashCyan,
                side: BorderSide(color: _cashCyan.withOpacity(.45)),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('cash-approve-all-categorised'),
              onPressed: () {
                final before = kaiCashPendingApprovalCount(_value.history);
                final history =
                    kaiApproveCategorisedCashTransactions(_value.history);
                final approved = before - kaiCashPendingApprovalCount(history);
                if (approved > 0) _update(_value.copyWith(history: history));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(approved == 0
                      ? 'No categorised transactions are waiting for approval.'
                      : 'Approved $approved categorised transaction${approved == 1 ? '' : 's'}.'),
                ));
              },
              icon: const Icon(Icons.done_all, size: 16),
              label: const Text('APPROVE CATEGORISED'),
            ),
            FilterChip(
              key: const Key('cash-history-uncategorised-filter'),
              selected: _historyOnlyUncategorised,
              label: const Text('Only uncategorised'),
              onSelected: (selected) =>
                  setState(() => _historyOnlyUncategorised = selected),
            ),
            FilterChip(
              key: const Key('cash-history-show-approved'),
              selected: _historyShowApproved,
              avatar: const Icon(Icons.check_circle_outline, size: 15),
              label: const Text('Show approved'),
              onSelected: (selected) =>
                  setState(() => _historyShowApproved = selected),
            ),
            Chip(
              avatar: const Icon(Icons.auto_awesome_outlined, size: 15),
              label: Text('${_value.categoryRules.length} learned rules'),
            ),
            Chip(
              key: const Key('cash-pending-approval-count'),
              avatar: Icon(
                pendingApproval == 0
                    ? Icons.verified_outlined
                    : Icons.pending_actions_outlined,
                size: 15,
                color: pendingApproval == 0 ? _cashGreen : _cashAmber,
              ),
              label: Text(
                pendingApproval == 0
                    ? 'All approved'
                    : '$pendingApproval left to approve',
                style: TextStyle(
                  color: pendingApproval == 0 ? _cashGreen : _cashAmber,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_value.categoryRules.isNotEmpty)
              OutlinedButton.icon(
                key: const Key('cash-apply-rules-to-history'),
                onPressed: () {
                  final history = kaiApplyCashRulesToHistory(
                    _value.history,
                    _value.categoryRules,
                  );
                  _update(_value.copyWith(history: history));
                },
                icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                label: const Text('Apply learned rules'),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        SizedBox(
          key: const Key('cash-history-chart'),
          height: 150,
          child: CustomPaint(painter: _CashHistoryPainter(records: sorted)),
        ),
        if (_value.categoryRules.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            key: const Key('cash-learned-rules'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            leading: const Icon(Icons.auto_awesome_outlined, color: _cashCyan),
            title: const Text('Learned merchant rules', style: _inputStyle),
            subtitle: const Text(
              'Local and deterministic. Delete any rule you do not want reused.',
              style: TextStyle(color: Color(0xFF7F94A5), fontSize: 9),
            ),
            children: _value.categoryRules
                .map((rule) => ListTile(
                      dense: true,
                      title: Text(rule.merchantKey, style: _inputStyle),
                      subtitle: Text(
                        rule.subcategory.isEmpty
                            ? rule.category
                            : '${rule.category} › ${rule.subcategory}',
                        style: const TextStyle(
                            color: Color(0xFF9FB6C8), fontSize: 9),
                      ),
                      trailing: IconButton(
                        tooltip: 'Forget rule',
                        onPressed: () => _update(_value.copyWith(
                          categoryRules: _value.categoryRules
                              .where((item) =>
                                  item.merchantKey != rule.merchantKey)
                              .toList(growable: false),
                        )),
                        icon: const Icon(Icons.delete_outline,
                            size: 16, color: Color(0xFFFF6B6B)),
                      ),
                    ))
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 10),
        for (final item in sorted) ...[
          _historyMonthCard(item),
          const SizedBox(height: 10),
        ],
        _addButton('Add historical month', () {
          final now = DateTime.now();
          final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
          final used = _value.history.map((item) => item.month).toSet();
          var candidate = month;
          var cursor = DateTime(now.year, now.month - 1);
          while (used.contains(candidate)) {
            candidate =
                '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
            cursor = DateTime(cursor.year, cursor.month - 1);
          }
          _update(_value.copyWith(history: [
            ..._value.history,
            KaiCashMonthRecord(month: candidate, income: 0, expenses: 0),
          ]));
        }),
      ],
    );
  }

  Future<void> _smartAssignHistory() async {
    final proposed =
        kaiSmartAssignCashHistory(_value.history, _value.categoryRules);
    final counts = <String, int>{};
    var changed = 0;
    for (var monthIndex = 0; monthIndex < _value.history.length; monthIndex++) {
      final before = _value.history[monthIndex].transactions;
      final after = proposed[monthIndex].transactions;
      for (var rowIndex = 0; rowIndex < before.length; rowIndex++) {
        if (before[rowIndex].category == after[rowIndex].category) continue;
        changed++;
        counts.update(after[rowIndex].category, (value) => value + 1,
            ifAbsent: () => 1);
      }
    }
    if (changed == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No confident matches found. Ambiguous transactions remain uncategorised.'),
      ));
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF101813),
        title: const Text('Review smart category assignment'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '$changed uncategorised transaction${changed == 1 ? '' : 's'} can be assigned using your learned rules and conservative merchant wording.',
              style: const TextStyle(color: Color(0xFFB7C9D5)),
            ),
            const SizedBox(height: 12),
            for (final entry in counts.entries) ...[
              Row(children: [
                Expanded(child: Text(entry.key, style: _inputStyle)),
                Text('${entry.value}',
                    style: const TextStyle(
                        color: _cashCyan, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 5),
            ],
            const SizedBox(height: 8),
            const Text(
              'Matched rows will also be approved and leave the review list. Reviewed categories, amounts, dates, accounts, and income/expense direction will not change.',
              style: TextStyle(color: Color(0xFF7F94A5), fontSize: 10),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('cash-confirm-smart-assign'),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: Text('Assign $changed'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      _update(_value.copyWith(history: proposed));
    }
  }

  Widget _historyMonthCard(KaiCashMonthRecord item) {
    final pendingApproval =
        item.transactions.where((transaction) => !transaction.approved).length;
    void replace(KaiCashMonthRecord next) {
      final history = _value.history
          .map((existing) => identical(existing, item) ? next : existing)
          .toList();
      _update(_value.copyWith(history: history));
    }

    return Container(
      key: Key('cash-history-card-${item.month}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(.09)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(
            width: 115,
            child: TextFormField(
              key: Key('cash-history-month-${item.month}'),
              initialValue: item.month,
              onChanged: (value) => replace(item.copyWith(month: value.trim())),
              style: _inputStyle,
              decoration: _inputDecoration('YYYY-MM'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: item.note,
              onChanged: (value) => replace(item.copyWith(note: value)),
              style: _inputStyle,
              decoration: _inputDecoration('Month note'),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            pendingApproval == 0
                ? 'ALL APPROVED'
                : '$pendingApproval TO APPROVE',
            key: Key('cash-month-pending-${item.month}'),
            style: TextStyle(
              color: pendingApproval == 0 ? _cashGreen : _cashAmber,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 12),
          Text('IN  BD ${_money(item.totalIncome)}',
              style: const TextStyle(
                  color: _cashGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Text('OUT  BD ${_money(item.totalExpenses)}',
              style: const TextStyle(
                  color: _cashAmber,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Text('NET  BD ${_signedMoney(item.cashFlow)}',
              style: TextStyle(
                  color:
                      item.cashFlow >= 0 ? _cashGreen : const Color(0xFFFF6B6B),
                  fontSize: 10,
                  fontWeight: FontWeight.w900)),
          IconButton(
            tooltip: 'Remove month',
            onPressed: () => _update(_value.copyWith(
              history: _value.history
                  .where((entry) => !identical(entry, item))
                  .toList(),
            )),
            icon: const Icon(Icons.delete_outline,
                size: 16, color: Color(0xFFFF6B6B)),
          ),
        ]),
        const SizedBox(height: 9),
        for (final transaction in kaiSortCashTransactions(
          item.transactions
              .where((transaction) =>
                  (_historyShowApproved || !transaction.approved) &&
                  (!_historyOnlyUncategorised ||
                      transaction.category == 'Uncategorised'))
              .toList(growable: false),
          _historySort,
        )) ...[
          _historyTransactionRow(item, transaction, replace),
          const SizedBox(height: 7),
        ],
        _addButton('Add transaction', () {
          replace(item.copyWith(transactions: [
            ...item.transactions,
            KaiCashTransaction(
              id: _id('history-transaction'),
              date: '${item.month}-01',
              source: '',
              description: '',
              category: 'Uncategorised',
              direction: KaiCashImportDirection.expense,
              amount: 0,
            ),
          ]));
        }),
        const SizedBox(height: 10),
        _monthSummary(item),
      ]),
    );
  }

  Widget _historyTransactionRow(
    KaiCashMonthRecord month,
    KaiCashTransaction item,
    ValueChanged<KaiCashMonthRecord> replaceMonth,
  ) {
    final index = month.transactions.indexWhere((entry) => entry.id == item.id);
    void replace(KaiCashTransaction next) {
      final rows = [...month.transactions]..[index] = next;
      replaceMonth(month.copyWith(transactions: rows));
    }

    void replaceAndLearn(KaiCashTransaction next) {
      final rows = [...month.transactions]..[index] = next;
      final nextMonth = month.copyWith(transactions: rows);
      final history = _value.history
          .map((existing) => identical(existing, month) ? nextMonth : existing)
          .toList(growable: false);
      final rules = kaiUpsertCashCategoryRule(
        rules: _value.categoryRules,
        description: next.description,
        category: next.category,
        subcategory: next.subcategory,
      );
      _update(_value.copyWith(history: history, categoryRules: rules));
    }

    Future<void> assignCategory(String category) async {
      final next = item.copyWith(category: category);
      final matching = kaiCashMatchingPendingCount(_value.history, item);
      if (matching <= 1 || category == 'Uncategorised') {
        replaceAndLearn(next);
        return;
      }
      final applyAll = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF101813),
          title: const Text('Categorise matching transactions?'),
          content: Text(
            '$matching pending transactions match this merchant. Apply “$category” to all of them and approve the group?',
            style: const TextStyle(color: Color(0xFFB7C9D5)),
          ),
          actions: [
            TextButton(
              key: const Key('cash-category-this-only'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('This transaction only'),
            ),
            FilledButton.icon(
              key: const Key('cash-category-apply-all'),
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.done_all, size: 16),
              label: Text('Apply + approve all $matching'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (applyAll == true) {
        final history = kaiCategoriseMatchingCashTransactions(
          history: _value.history,
          target: item,
          category: category,
          subcategory: item.subcategory,
        );
        final rules = kaiUpsertCashCategoryRule(
          rules: _value.categoryRules,
          description: item.description,
          category: category,
          subcategory: item.subcategory,
        );
        _update(_value.copyWith(history: history, categoryRules: rules));
      } else {
        replaceAndLearn(next);
      }
    }

    return Container(
      key: Key('cash-history-transaction-${item.id}'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1821),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: item.approved
                    ? 'Mark as needing review'
                    : 'Approve and remove from review list',
                child: Checkbox(
                  key: Key('cash-approve-transaction-${item.id}'),
                  value: item.approved,
                  activeColor: _cashGreen,
                  onChanged: (value) =>
                      replace(item.copyWith(approved: value ?? false)),
                ),
              ),
              SizedBox(
                width: 118,
                child: TextFormField(
                  initialValue: item.date,
                  onChanged: (value) =>
                      replace(item.copyWith(date: value.trim())),
                  style: _inputStyle,
                  decoration: _inputDecoration('YYYY-MM-DD'),
                ),
              ),
              SizedBox(
                width: 145,
                child: DropdownButtonFormField<KaiCashImportDirection>(
                  value: item.direction,
                  dropdownColor: const Color(0xFF18221C),
                  decoration: _inputDecoration(''),
                  style: _inputStyle,
                  items: const [
                    DropdownMenuItem(
                        value: KaiCashImportDirection.income,
                        child: Text('Income')),
                    DropdownMenuItem(
                        value: KaiCashImportDirection.expense,
                        child: Text('Expense')),
                  ],
                  onChanged: (value) {
                    if (value != null) replace(item.copyWith(direction: value));
                  },
                ),
              ),
              SizedBox(
                width: 420,
                child: TextFormField(
                  initialValue: item.description,
                  onChanged: (value) =>
                      replace(item.copyWith(description: value)),
                  style: _inputStyle,
                  decoration: _inputDecoration('Description / merchant'),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextFormField(
                  initialValue: _editableNumber(item.amount),
                  onChanged: (value) => replace(item.copyWith(
                      amount: double.tryParse(value)?.abs() ?? 0)),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: _inputStyle,
                  decoration: _inputDecoration('Amount'),
                ),
              ),
              IconButton(
                tooltip: 'Remove transaction',
                onPressed: () {
                  final rows = [...month.transactions]..removeAt(index);
                  replaceMonth(month.copyWith(transactions: rows));
                },
                icon:
                    const Icon(Icons.close, size: 15, color: Color(0xFFFF6B6B)),
              ),
            ]),
        const SizedBox(height: 7),
        Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: _accountSourceEditor(
                  value: item.source,
                  keyPrefix: 'cash-history-${item.id}',
                  onChanged: (value) => replace(item.copyWith(source: value)),
                ),
              ),
              SizedBox(
                width: 390,
                child: _categoryPicker(
                  value: item.category,
                  keyPrefix: 'cash-history-${item.id}',
                  onChanged: (value) => unawaited(assignCategory(value)),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextFormField(
                  initialValue: item.subcategory,
                  onChanged: (value) =>
                      replaceAndLearn(item.copyWith(subcategory: value)),
                  style: _inputStyle,
                  decoration: _inputDecoration('Subcategory'),
                ),
              ),
            ]),
      ]),
    );
  }

  Widget _monthSummary(KaiCashMonthRecord month) {
    final summary = kaiSummariseCashMonth(month);
    Widget lines(Map<String, double> values, {required bool signed}) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: values.entries.take(8).map((entry) {
            final amount =
                signed ? _signedMoney(entry.value) : _money(entry.value);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(
                  child: Text(entry.key,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFB7C9D5), fontSize: 10)),
                ),
                Text('BD $amount',
                    style: TextStyle(
                        color: signed && entry.value >= 0
                            ? _cashGreen
                            : _cashAmber,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ]),
            );
          }).toList(growable: false),
        );
    return Container(
      key: Key('cash-month-summary-${month.month}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _cashCyan.withOpacity(.035),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _cashCyan.withOpacity(.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.summarize_outlined, size: 16, color: _cashCyan),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('MONTH-END SUMMARY',
                style: TextStyle(
                    color: _cashCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8)),
          ),
          Text('${summary.uncategorisedCount} uncategorised',
              style: TextStyle(
                  color:
                      summary.uncategorisedCount == 0 ? _cashGreen : _cashAmber,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 9),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('SPENDING BY CATEGORY',
                      style: TextStyle(color: Colors.white70, fontSize: 9)),
                  const SizedBox(height: 6),
                  lines(summary.spendingByCategory, signed: false),
                ]),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('NET MOVEMENT BY ACCOUNT',
                      style: TextStyle(color: Colors.white70, fontSize: 9)),
                  const SizedBox(height: 6),
                  lines(summary.netByAccount, signed: true),
                ]),
          ),
        ]),
      ]),
    );
  }

  Widget _accountsSection() {
    return _section(
      title: 'Recognised accounts',
      icon: Icons.account_balance_outlined,
      total: 0,
      children: [
        const Text(
          'Name your regular accounts and add matching clues such as an account number, last four digits, bank label, or statement filename phrase. During import, the longest matching clue wins. Homecoming only labels the source; every transaction remains editable.',
          style: TextStyle(color: Color(0xFF9FB6C8), fontSize: 10),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < _value.accounts.length; index++) ...[
          _accountRow(index),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          key: const Key('cash-add-account'),
          onPressed: () => _update(_value.copyWith(accounts: [
            ..._value.accounts,
            KaiCashAccount(
              id: _id('account'),
              name: '',
              owner: 'Mine',
            ),
          ])),
          icon: const Icon(Icons.add, size: 17),
          label: const Text('Add account'),
        ),
        if (_value.accounts.isNotEmpty && _value.history.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('cash-apply-accounts-to-history'),
            onPressed: () {
              final history = kaiLabelCashHistoryAccounts(
                _value.history,
                _value.accounts,
              );
              final changed = Iterable<int>.generate(_value.history.length)
                  .expand((monthIndex) => Iterable<int>.generate(
                        _value.history[monthIndex].transactions.length,
                      ).map((rowIndex) => _value.history[monthIndex]
                                  .transactions[rowIndex].source !=
                              history[monthIndex].transactions[rowIndex].source
                          ? 1
                          : 0))
                  .fold<int>(0, (sum, value) => sum + value);
              if (changed > 0) _update(_value.copyWith(history: history));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(changed == 0
                    ? 'No existing source labels matched these account clues.'
                    : 'Relabelled $changed existing transaction source${changed == 1 ? '' : 's'}.'),
              ));
            },
            icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
            label: const Text('Apply matches to existing history'),
          ),
        ],
      ],
    );
  }

  Widget _accountRow(int index) {
    final account = _value.accounts[index];
    void replace(KaiCashAccount next) {
      final accounts = [..._value.accounts]..[index] = next;
      _update(_value.copyWith(accounts: accounts));
    }

    return Container(
      key: Key('cash-account-${account.id}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.025),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Row(children: [
        SizedBox(
          width: 135,
          child: DropdownButtonFormField<String>(
            key: Key('cash-account-owner-${account.id}'),
            value: account.owner,
            isExpanded: true,
            dropdownColor: const Color(0xFF18221C),
            decoration: _inputDecoration('Owner'),
            style: _inputStyle,
            items: const ['Mine', 'Wife', 'Company', 'Other']
                .map((owner) => DropdownMenuItem(
                      value: owner,
                      child: Text(owner),
                    ))
                .toList(growable: false),
            onChanged: (owner) {
              if (owner != null) replace(account.copyWith(owner: owner));
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            key: Key('cash-account-name-${account.id}'),
            initialValue: account.name,
            onChanged: (name) => replace(account.copyWith(name: name)),
            style: _inputStyle,
            decoration: _inputDecoration('Account name'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: TextFormField(
            key: Key('cash-account-aliases-${account.id}'),
            initialValue: account.aliases.join(', '),
            onChanged: (value) => replace(account.copyWith(
              aliases: value
                  .split(',')
                  .map((alias) => alias.trim())
                  .where((alias) => alias.isNotEmpty)
                  .toSet()
                  .toList(growable: false),
            )),
            style: _inputStyle,
            decoration: _inputDecoration('Matching clues, separated by commas'),
          ),
        ),
        IconButton(
          tooltip: 'Remove account',
          onPressed: () => _update(_value.copyWith(
            accounts: [..._value.accounts]..removeAt(index),
          )),
          icon: const Icon(Icons.delete_outline,
              size: 17, color: Color(0xFFFF6B6B)),
        ),
      ]),
    );
  }

  Widget _statementImportSection() {
    final selected = _importCandidates.where((item) => item.selected).length;
    return _section(
      title: 'Statement import review',
      icon: Icons.upload_file_outlined,
      total: 0,
      children: [
        const Text(
          'Choose CSV, TXT, or a text-based PDF. Every extracted field is editable before import. Homecoming stores nothing until you review and import selected rows. Scanned-image PDFs need OCR and are rejected here.',
          style: TextStyle(color: Color(0xFF9FB6C8), fontSize: 10),
        ),
        const SizedBox(height: 10),
        Row(children: [
          OutlinedButton.icon(
            key: const Key('cash-upload-statement'),
            onPressed: _importBusy ? null : _pickStatement,
            icon: _importBusy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.file_open_outlined, size: 17),
            label: const Text('Upload statement'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_importStatus,
                style: const TextStyle(color: Color(0xFF9FB6C8), fontSize: 10)),
          ),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('cash-import-add-category'),
            onPressed: _addCategory,
            icon: const Icon(Icons.create_new_folder_outlined, size: 16),
            label: const Text('Add reusable category'),
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < _importCandidates.length; index++) ...[
          _importCandidateRow(index),
          const SizedBox(height: 7),
        ],
        if (_importCandidates.isNotEmpty)
          FilledButton.icon(
            key: const Key('cash-import-selected'),
            onPressed: selected == 0 ? null : _importSelected,
            icon: const Icon(Icons.playlist_add_check, size: 18),
            label: Text('Import $selected selected into history'),
            style: FilledButton.styleFrom(
                backgroundColor: _cashCyan, foregroundColor: Colors.black),
          ),
      ],
    );
  }

  Widget _importCandidateRow(int index) {
    final item = _importCandidates[index];
    void replace(KaiCashImportCandidate next) {
      setState(() {
        _importCandidates = [..._importCandidates]..[index] = next;
      });
    }

    void replaceAndLearn(KaiCashImportCandidate next) {
      final rules = kaiUpsertCashCategoryRule(
        rules: _value.categoryRules,
        description: next.description,
        category: next.category,
        subcategory: next.subcategory,
      );
      setState(() {
        _importCandidates = [..._importCandidates]..[index] = next;
        _value = _value.copyWith(categoryRules: rules);
      });
      unawaited(KaiPersonalCashStore.instance.save(_value));
    }

    return Container(
      key: Key('cash-import-candidate-$index'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.025),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: Column(children: [
        Row(children: [
          Checkbox(
            value: item.selected,
            onChanged: (value) =>
                replace(item.copyWith(selected: value ?? false)),
          ),
          SizedBox(
            width: 118,
            child: TextFormField(
              initialValue: item.date,
              onChanged: (value) => replace(item.copyWith(date: value.trim())),
              style: _inputStyle,
              decoration: _inputDecoration('YYYY-MM-DD'),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: TextFormField(
              initialValue: item.description,
              onChanged: (value) => replace(item.copyWith(description: value)),
              style: _inputStyle,
              decoration: _inputDecoration('Description'),
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            width: 145,
            child: DropdownButtonFormField<KaiCashImportDirection>(
              value: item.direction,
              dropdownColor: const Color(0xFF18221C),
              decoration: _inputDecoration(''),
              style: _inputStyle,
              items: const [
                DropdownMenuItem(
                    value: KaiCashImportDirection.income,
                    child: Text('Income')),
                DropdownMenuItem(
                    value: KaiCashImportDirection.expense,
                    child: Text('Expense')),
              ],
              onChanged: (value) {
                if (value != null) replace(item.copyWith(direction: value));
              },
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            width: 105,
            child: TextFormField(
              initialValue: _editableNumber(item.amount),
              onChanged: (value) => replace(
                  item.copyWith(amount: double.tryParse(value)?.abs() ?? 0)),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: _inputStyle,
              decoration: _inputDecoration('Amount'),
            ),
          ),
        ]),
        const SizedBox(height: 7),
        Row(children: [
          const SizedBox(width: 48),
          Expanded(
            child: _accountSourceEditor(
              value: item.source,
              keyPrefix: 'cash-import-$index',
              onChanged: (value) => replace(item.copyWith(source: value)),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _categoryPicker(
              value: item.category,
              keyPrefix: 'cash-import-$index',
              onChanged: (value) =>
                  replaceAndLearn(item.copyWith(category: value)),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: TextFormField(
              initialValue: item.subcategory,
              onChanged: (value) =>
                  replaceAndLearn(item.copyWith(subcategory: value)),
              style: _inputStyle,
              decoration: _inputDecoration('Subcategory'),
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _pickStatement() async {
    setState(() {
      _importBusy = true;
      _importStatus = 'Opening local file picker…';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt', 'pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _importStatus = 'Import cancelled.');
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('The selected statement is empty.');
      }
      final extension = (file.extension ?? '').toLowerCase();
      String text;
      if (extension == 'pdf') {
        text = KaiCashStatementParser.extractPdfText(bytes);
      } else {
        text = utf8.decode(bytes, allowMalformed: true);
      }
      final parsedCandidates = KaiCashStatementParser.parse(
        text,
        source: file.name,
      );
      final recognisedAccount = kaiRecogniseCashAccount(
        _value.accounts,
        '${file.name}\n$text',
      );
      final accountCandidates = recognisedAccount == null
          ? parsedCandidates
          : parsedCandidates
              .map((candidate) =>
                  candidate.copyWith(source: recognisedAccount.name.trim()))
              .toList(growable: false);
      final candidates =
          kaiSmartAssignCashCandidates(accountCandidates, _value.categoryRules);
      final learnedMatches = Iterable<int>.generate(candidates.length)
          .where((index) =>
              parsedCandidates[index].category == 'Uncategorised' &&
              candidates[index].category != 'Uncategorised')
          .length;
      if (!mounted) return;
      setState(() {
        _importCandidates = candidates;
        _importStatus = candidates.isEmpty
            ? 'No transaction rows found. Scanned PDFs are not supported; try a CSV export or text-based PDF.'
            : '${candidates.length} candidate transactions found${recognisedAccount == null ? '' : ' for ${recognisedAccount.name} (${recognisedAccount.owner})'}; $learnedMatches categorised from your local rules. Review every row before importing.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _importCandidates = const [];
          _importStatus = 'Could not read this statement: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _importBusy = false);
    }
  }

  void _importSelected() {
    final result = kaiMergeStatementCandidates(
      history: _value.history,
      candidates: _importCandidates,
      nextId: () => _id('statement-transaction'),
    );
    _update(_value.copyWith(history: result.history));
    setState(() {
      _importCandidates = const [];
      _importStatus =
          '${result.imported} transactions imported; ${result.duplicates} duplicates and ${result.invalid} invalid rows skipped. Original statement not retained.';
    });
  }

  Widget _holdingSection() => _section(
        title: 'Savings & investments',
        icon: Icons.candlestick_chart_outlined,
        total: _value.savingsAndInvestmentsValue,
        children: [
          for (var i = 0; i < _value.investments.length; i++) ...[
            _holdingRow(i),
            const SizedBox(height: 7),
          ],
          _addButton('Add savings or investment', () {
            _update(_value.copyWith(investments: [
              ..._value.investments,
              KaiCashHolding(
                  id: _id('holding'), label: '', value: 0, kind: 'Savings'),
            ]));
          }),
        ],
      );

  Widget _holdingRow(int index) {
    final item = _value.investments[index];
    void replace(KaiCashHolding next) {
      final copy = [..._value.investments]..[index] = next;
      _update(_value.copyWith(investments: copy));
    }

    return Row(children: [
      SizedBox(
        width: 125,
        child: DropdownButtonFormField<String>(
          key: Key('cash-holding-kind-${item.id}'),
          value: item.kind,
          isExpanded: true,
          dropdownColor: const Color(0xFF18221C),
          decoration: _inputDecoration('Type'),
          style: _inputStyle,
          items: const [
            DropdownMenuItem(value: 'Savings', child: Text('Savings')),
            DropdownMenuItem(value: 'Investment', child: Text('Investment')),
          ],
          onChanged: (value) {
            if (value != null) replace(item.copyWith(kind: value));
          },
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: TextFormField(
          initialValue: item.label,
          onChanged: (v) => replace(item.copyWith(label: v)),
          style: _inputStyle,
          decoration: _inputDecoration(
              item.kind == 'Savings' ? 'Savings account / goal' : 'Holding'),
        ),
      ),
      const SizedBox(width: 7),
      SizedBox(
        width: 110,
        child: TextFormField(
          initialValue: _editableNumber(item.value),
          onChanged: (v) =>
              replace(item.copyWith(value: double.tryParse(v) ?? 0)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: _inputStyle,
          decoration: _inputDecoration('Value'),
        ),
      ),
      IconButton(
        tooltip: 'Remove',
        onPressed: () {
          final copy = [..._value.investments]..removeAt(index);
          _update(_value.copyWith(investments: copy));
        },
        icon: const Icon(Icons.close, size: 15, color: Color(0xFF9FB6C8)),
      ),
    ]);
  }

  Widget _debtSection() => _section(
        title: 'Debts and payables',
        icon: Icons.account_balance_outlined,
        total: _value.debtBalance,
        children: [
          for (var i = 0; i < _value.debts.length; i++) ...[
            _debtRow(i),
            const SizedBox(height: 7),
          ],
          _addButton('Add debt or payable', () {
            _update(_value.copyWith(debts: [
              ..._value.debts,
              KaiCashDebt(id: _id('debt'), label: '', kind: 'Debt', balance: 0),
            ]));
          }),
        ],
      );

  Widget _debtRow(int index) {
    final item = _value.debts[index];
    void replace(KaiCashDebt next) {
      final copy = [..._value.debts]..[index] = next;
      _update(_value.copyWith(debts: copy));
    }

    return Row(children: [
      Expanded(
        flex: 4,
        child: TextFormField(
          initialValue: item.label,
          onChanged: (v) => replace(item.copyWith(label: v)),
          style: _inputStyle,
          decoration: _inputDecoration('Name'),
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        flex: 3,
        child: DropdownButtonFormField<String>(
          value: item.kind,
          isExpanded: true,
          dropdownColor: const Color(0xFF18221C),
          decoration: _inputDecoration(''),
          style: _inputStyle,
          items: const [
            DropdownMenuItem(value: 'Debt', child: Text('Debt')),
            DropdownMenuItem(value: 'Payable', child: Text('Payable')),
          ],
          onChanged: (v) {
            if (v != null) replace(item.copyWith(kind: v));
          },
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        flex: 3,
        child: TextFormField(
          initialValue: _editableNumber(item.balance),
          onChanged: (v) =>
              replace(item.copyWith(balance: double.tryParse(v) ?? 0)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: _inputStyle,
          decoration: _inputDecoration('Balance'),
        ),
      ),
      IconButton(
        tooltip: 'Remove',
        onPressed: () {
          final copy = [..._value.debts]..removeAt(index);
          _update(_value.copyWith(debts: copy));
        },
        icon: const Icon(Icons.close, size: 15, color: Color(0xFF9FB6C8)),
      ),
    ]);
  }

  Widget _section({
    required String title,
    required IconData icon,
    required double total,
    required List<Widget> children,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _cashPanel.withOpacity(0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14))),
              Text('BD ${_money(total)}',
                  style: const TextStyle(
                      color: _cashAmber,
                      fontWeight: FontWeight.w900,
                      fontSize: 13)),
            ]),
            const SizedBox(height: 11),
            ...children,
          ],
        ),
      );

  Widget _addButton(String label, VoidCallback onPressed) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add, size: 17),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withOpacity(0.18)),
          ),
        ),
      );

  Widget _labelledField(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _smallStyle),
          const SizedBox(height: 5),
          child,
        ],
      );
}

class _CashHistoryPainter extends CustomPainter {
  const _CashHistoryPainter({required this.records});
  final List<KaiCashMonthRecord> records;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withOpacity(.07)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = 8 + (size.height - 28) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (records.isEmpty) {
      final text = TextPainter(
          text: const TextSpan(
              text: 'Add past months to reveal income and spending patterns',
              style: TextStyle(color: Color(0xFF71899A), fontSize: 10)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width);
      text.paint(
          canvas,
          Offset(
              (size.width - text.width) / 2, (size.height - text.height) / 2));
      return;
    }
    final maximum = records
        .expand((item) => [item.totalIncome, item.totalExpenses])
        .fold<double>(1, math.max);
    double y(double value) =>
        8 + (size.height - 32) * (1 - (value / maximum).clamp(0, 1));
    void drawSeries(double Function(KaiCashMonthRecord) value, Color color) {
      final path = Path();
      for (var i = 0; i < records.length; i++) {
        final x = records.length == 1
            ? size.width / 2
            : size.width * i / (records.length - 1);
        final point = Offset(x, y(value(records[i])));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawCircle(point, 3, Paint()..color = color);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke);
    }

    drawSeries((item) => item.totalIncome, _cashGreen);
    drawSeries((item) => item.totalExpenses, _cashAmber);
    final legend = TextPainter(
        text: const TextSpan(children: [
          TextSpan(
              text: 'INCOME  ',
              style: TextStyle(color: _cashGreen, fontSize: 8)),
          TextSpan(
              text: 'SPENDING',
              style: TextStyle(color: _cashAmber, fontSize: 8)),
        ]),
        textDirection: TextDirection.ltr)
      ..layout();
    legend.paint(canvas, Offset(size.width - legend.width, size.height - 12));
  }

  @override
  bool shouldRepaint(covariant _CashHistoryPainter oldDelegate) =>
      oldDelegate.records != records;
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric(
    this.label,
    this.value, {
    this.color = Colors.white,
    this.signed = false,
  });

  final String label;
  final double value;
  final Color color;
  final bool signed;

  @override
  Widget build(BuildContext context) => Container(
        width: 190,
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
        decoration: BoxDecoration(
          color: _cashPanel.withOpacity(0.72),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BD ${signed ? _signedMoney(value) : _money(value)}',
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: _tinyStyle),
          ],
        ),
      );
}

InputDecoration _inputDecoration(String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF66766C)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      filled: true,
      fillColor: const Color(0xFF1A241D),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _cashCyan),
      ),
    );

const _inputStyle = TextStyle(color: Colors.white, fontSize: 12);
const _smallStyle = TextStyle(color: Color(0xFFB9C9BE), fontSize: 10.5);
const _tinyStyle = TextStyle(
  color: Color(0xFF8FA39A),
  fontSize: 8,
  letterSpacing: 0.7,
  fontFamily: 'monospace',
);

String _editableNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

String _money(double value) {
  final absolute = value.abs();
  final parts = _editableNumber(absolute).split('.');
  final digits = parts.first;
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  if (parts.length > 1) out.write('.${parts[1]}');
  return out.toString();
}

String _signedMoney(double value) =>
    '${value >= 0 ? '+' : '-'}${_money(value)}';
