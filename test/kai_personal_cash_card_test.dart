import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/kai_cash_statement_parser.dart';
import 'package:homecoming_app/widgets/kai_personal_cash_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('seeded cash evidence reproduces the supplied breakdown exactly', () {
    const value = KaiPersonalCashSnapshot.seeded;

    expect(value.monthlyIncome, 4995);
    expect(value.monthlyExpenses, 1020);
    expect(value.monthlyCashFlow, 3975);
    expect(value.investmentValue, 0);
    expect(value.debtBalance, 7275);
    expect(value.safeToSpend, 0);
  });

  test('cash snapshot round-trips without changing proof values', () {
    const original = KaiPersonalCashSnapshot.seeded;
    final restored = KaiPersonalCashSnapshot.fromJson(
      jsonDecode(jsonEncode(original.toJson())),
    );

    expect(restored, isNotNull);
    expect(restored!.monthlyIncome, original.monthlyIncome);
    expect(restored.monthlyExpenses, original.monthlyExpenses);
    expect(restored.debtBalance, original.debtBalance);
    expect(
        restored.income.map((item) => item.label), ['Moon plaza', 'Levendome']);
    expect(restored.debts.map((item) => item.label),
        ['Rent arrears', 'Alsalam CC', 'Credimax']);
  });

  test('version 1 cash data migrates with empty history and flat expenses', () {
    final restored = KaiPersonalCashSnapshot.fromJson({
      'version': 1,
      'income': const [],
      'expenses': [
        {'id': 'rent', 'label': 'Rent', 'amount': 850, 'cadence': 'monthly'}
      ],
      'investments': const [],
      'debts': const [],
    });
    expect(restored, isNotNull);
    expect(restored!.history, isEmpty);
    expect(restored.expenses.single.children, isEmpty);
    expect(restored.monthlyExpenses, 850);
  });

  test('expense subcategories determine parent total without double counting',
      () {
    const subscriptions = KaiCashFlowLine(
      id: 'subscriptions',
      label: 'Subscriptions & memberships',
      amount: 999,
      children: [
        KaiCashFlowLine(id: 'netflix', label: 'Netflix', amount: 6),
        KaiCashFlowLine(id: 'disney', label: 'Disney+', amount: 4),
        KaiCashFlowLine(
            id: 'yearly-gym',
            label: 'Gym',
            amount: 120,
            cadence: KaiCashCadence.yearly),
      ],
    );
    expect(subscriptions.monthlyAmount, 20);
    final restored = KaiCashFlowLine.fromJson(
        jsonDecode(jsonEncode(subscriptions.toJson())))!;
    expect(restored.children.map((item) => item.label),
        ['Netflix', 'Disney+', 'Gym']);
    expect(restored.monthlyAmount, 20);
  });

  test('savings and investments remain distinct while sharing an asset total',
      () {
    const original = KaiPersonalCashSnapshot(
      income: [],
      expenses: [],
      investments: [
        KaiCashHolding(
            id: 'buffer',
            label: 'Emergency fund',
            value: 1200,
            kind: 'Savings'),
        KaiCashHolding(id: 'shares', label: 'Index fund', value: 800),
      ],
      debts: [],
    );
    final restored = KaiPersonalCashSnapshot.fromJson(
        jsonDecode(jsonEncode(original.toJson())))!;
    expect(restored.savingsValue, 1200);
    expect(restored.investmentValue, 800);
    expect(restored.savingsAndInvestmentsValue, 2000);
    expect(restored.investments.first.kind, 'Savings');
    expect(restored.investments.last.kind, 'Investment');
  });

  test('historical months sort and round-trip with cash flow intact', () {
    const original = KaiPersonalCashSnapshot(
      income: [],
      expenses: [],
      investments: [],
      debts: [],
      history: [
        KaiCashMonthRecord(
            month: '2026-06', income: 4000, expenses: 3100, note: 'Travel'),
        KaiCashMonthRecord(month: '2026-07', income: 4200, expenses: 2800),
      ],
    );
    final restored = KaiPersonalCashSnapshot.fromJson(
        jsonDecode(jsonEncode(original.toJson())))!;
    expect(restored.history.length, 2);
    expect(restored.history.first.cashFlow, 900);
    expect(restored.history.last.cashFlow, 1400);
    expect(restored.history.first.note, 'Travel');
  });

  test('legacy summary month migrates into editable transaction breakdown', () {
    final restored = KaiCashMonthRecord.fromJson({
      'month': '2026-07',
      'income': 4200,
      'expenses': 2800,
      'note': 'legacy',
    })!;

    expect(restored.transactions.length, 2);
    expect(restored.transactions.first.description, 'Historical income total');
    expect(restored.totalIncome, 4200);
    expect(restored.totalExpenses, 2800);
    expect(restored.cashFlow, 1400);
  });

  test('transaction-level history and receivables round-trip exactly', () {
    const original = KaiPersonalCashSnapshot(
      income: [],
      expenses: [],
      investments: [],
      debts: [],
      receivables: [
        KaiCashReceivable(
          id: 'salary-due',
          source: 'Moon Plaza',
          amount: 3050,
          expectedDate: '2026-08-28',
        ),
      ],
      history: [
        KaiCashMonthRecord(
          month: '2026-07',
          income: 0,
          expenses: 0,
          transactions: [
            KaiCashTransaction(
              id: 'salary',
              date: '2026-07-28',
              source: 'Bank account',
              description: 'Salary',
              category: 'Income',
              direction: KaiCashImportDirection.income,
              amount: 4000,
            ),
            KaiCashTransaction(
              id: 'netflix',
              date: '2026-07-12',
              source: 'Credit card',
              description: 'Netflix',
              category: 'Subscriptions & memberships',
              subcategory: 'Netflix',
              direction: KaiCashImportDirection.expense,
              amount: 6,
            ),
          ],
        ),
      ],
    );

    final restored = KaiPersonalCashSnapshot.fromJson(
        jsonDecode(jsonEncode(original.toJson())))!;
    expect(restored.receivables.single.source, 'Moon Plaza');
    expect(restored.receivables.single.expectedDate, '2026-08-28');
    expect(restored.history.single.totalIncome, 4000);
    expect(restored.history.single.totalExpenses, 6);
    expect(restored.history.single.transactions.last.subcategory, 'Netflix');
  });

  test('custom categories persist and statement fields remain fully editable',
      () {
    const snapshot = KaiPersonalCashSnapshot(
      income: [],
      expenses: [],
      investments: [],
      debts: [],
      customCategories: ['Subscriptions & memberships', 'Dining'],
    );
    final restored = KaiPersonalCashSnapshot.fromJson(
      jsonDecode(jsonEncode(snapshot.toJson())),
    )!;
    expect(
        restored.customCategories, ['Subscriptions & memberships', 'Dining']);

    const extracted = KaiCashImportCandidate(
      date: '2026-08-01',
      description: 'RAW MERCHANT',
      amount: 12,
      direction: KaiCashImportDirection.expense,
      source: 'statement.pdf',
    );
    final reviewed = extracted.copyWith(
      date: '2026-08-02',
      description: 'Netflix',
      amount: 6,
      direction: KaiCashImportDirection.income,
      source: 'Credit card',
      category: 'Subscriptions & memberships',
      subcategory: 'Netflix',
      selected: false,
    );
    expect(reviewed.date, '2026-08-02');
    expect(reviewed.description, 'Netflix');
    expect(reviewed.amount, 6);
    expect(reviewed.direction, KaiCashImportDirection.income);
    expect(reviewed.source, 'Credit card');
    expect(reviewed.category, 'Subscriptions & memberships');
    expect(reviewed.subcategory, 'Netflix');
    expect(reviewed.selected, isFalse);
  });

  test('recognised accounts round-trip with owner and matching aliases', () {
    const snapshot = KaiPersonalCashSnapshot(
      income: [],
      expenses: [],
      investments: [],
      debts: [],
      accounts: [
        KaiCashAccount(
          id: 'personal-alsalam',
          name: 'My Al Salam account',
          owner: 'Mine',
          aliases: ['693594150000', 'personal-july-statement'],
        ),
        KaiCashAccount(
          id: 'company-account',
          name: 'Company operating account',
          owner: 'Company',
          aliases: ['company-current-8842'],
        ),
      ],
    );

    final restored = KaiPersonalCashSnapshot.fromJson(
      jsonDecode(jsonEncode(snapshot.toJson())),
    )!;
    expect(restored.accounts, hasLength(2));
    expect(restored.accounts.first.owner, 'Mine');
    expect(restored.accounts.first.aliases, contains('693594150000'));
    expect(restored.accounts.last.owner, 'Company');
  });

  test('account recognition is case-insensitive and longest alias wins', () {
    const accounts = [
      KaiCashAccount(
        id: 'generic',
        name: 'My account',
        owner: 'Mine',
        aliases: ['Al Salam'],
      ),
      KaiCashAccount(
        id: 'specific',
        name: 'Wife Al Salam account',
        owner: 'Wife',
        aliases: ['AL SALAM 7788', '7788'],
      ),
    ];

    expect(
      kaiRecogniseCashAccount(accounts, 'Statement: al salam 7788 July')?.id,
      'specific',
    );
    expect(kaiRecogniseCashAccount(accounts, 'unrelated statement'), isNull);
  });

  test('aliases shorter than three characters cannot identify an account', () {
    const accounts = [
      KaiCashAccount(
        id: 'unsafe',
        name: 'Company account',
        owner: 'Company',
        aliases: ['42'],
      ),
    ];
    expect(kaiRecogniseCashAccount(accounts, 'payment reference 42'), isNull);
  });

  test('existing history relabelling changes only matched transaction sources',
      () {
    const history = [
      KaiCashMonthRecord(
        month: '2026-07',
        income: 0,
        expenses: 0,
        transactions: [
          KaiCashTransaction(
            id: 'matched',
            date: '2026-07-01',
            source: 'AccountMovements_693594150000_July_2026.pdf',
            description: 'Merchant',
            category: 'Dining',
            direction: KaiCashImportDirection.expense,
            amount: 11.55,
            importFingerprint: 'immutable-import-id',
          ),
          KaiCashTransaction(
            id: 'unmatched',
            date: '2026-07-02',
            source: 'cash',
            description: 'Other merchant',
            category: 'Other',
            direction: KaiCashImportDirection.expense,
            amount: 2,
          ),
        ],
      ),
    ];
    const accounts = [
      KaiCashAccount(
        id: 'mine',
        name: 'My Al Salam account',
        owner: 'Mine',
        aliases: ['693594150000'],
      ),
    ];

    final relabelled = kaiLabelCashHistoryAccounts(history, accounts);
    expect(relabelled.single.transactions.first.source, 'My Al Salam account');
    expect(relabelled.single.transactions.first.amount, 11.55);
    expect(relabelled.single.transactions.first.category, 'Dining');
    expect(relabelled.single.transactions.first.importFingerprint,
        'immutable-import-id');
    expect(relabelled.single.transactions.last.source, 'cash');
  });

  test('manual merchant category becomes a persistent local rule', () {
    final rules = kaiUpsertCashCategoryRule(
      rules: const [],
      description:
          'VISA CARD POS TRANSACTION Debit Card Switch Account USD, NETFLIX.COM',
      category: 'Subscriptions & memberships',
      subcategory: 'Netflix',
    );
    expect(rules, hasLength(1));
    expect(rules.single.merchantKey, 'netflix com');

    final restored = KaiPersonalCashSnapshot.fromJson(jsonDecode(jsonEncode(
      KaiPersonalCashSnapshot(
        income: const [],
        expenses: const [],
        investments: const [],
        debts: const [],
        categoryRules: rules,
      ).toJson(),
    )))!;
    expect(
        restored.categoryRules.single.category, 'Subscriptions & memberships');
    expect(restored.categoryRules.single.subcategory, 'Netflix');
  });

  test(
      'learned rules fill future uncategorised rows but never overwrite review',
      () {
    const rule = KaiCashCategoryRule(
      merchantKey: 'netflix com',
      category: 'Subscriptions',
      subcategory: 'Netflix',
    );
    const candidates = [
      KaiCashImportCandidate(
        date: '2026-08-01',
        description: 'POS PURCHASE NETFLIX.COM',
        amount: 6,
        direction: KaiCashImportDirection.expense,
        source: 'card',
      ),
      KaiCashImportCandidate(
        date: '2026-08-02',
        description: 'POS PURCHASE NETFLIX.COM',
        amount: 7,
        direction: KaiCashImportDirection.expense,
        source: 'card',
        category: 'Business expense',
      ),
    ];
    final result = kaiApplyCashCategoryRules(candidates, const [rule]);
    expect(result.first.category, 'Subscriptions');
    expect(result.first.subcategory, 'Netflix');
    expect(result.last.category, 'Business expense');
  });

  test('smart assignment uses conservative clues and leaves ambiguity alone',
      () {
    const candidates = [
      KaiCashImportCandidate(
        date: '2026-08-01',
        description: 'JUFAIR MARINA PHARMACY',
        amount: 11.55,
        direction: KaiCashImportDirection.expense,
        source: 'My account',
      ),
      KaiCashImportCandidate(
        date: '2026-08-02',
        description: 'NETFLIX.COM',
        amount: 6,
        direction: KaiCashImportDirection.expense,
        source: 'My account',
      ),
      KaiCashImportCandidate(
        date: '2026-08-03',
        description: 'UNKNOWN SHOP W.L.L.',
        amount: 4,
        direction: KaiCashImportDirection.expense,
        source: 'My account',
      ),
      KaiCashImportCandidate(
        date: '2026-08-04',
        description: 'SUPERMARKET',
        amount: 9,
        direction: KaiCashImportDirection.expense,
        source: 'My account',
        category: 'Business expense',
      ),
    ];
    final result = kaiSmartAssignCashCandidates(candidates, const []);
    expect(result[0].category, 'Health & pharmacy');
    expect(result[1].category, 'Subscriptions & memberships');
    expect(result[2].category, 'Uncategorised');
    expect(result[3].category, 'Business expense');
  });

  test('learned rule has priority over built-in merchant wording', () {
    const rules = [
      KaiCashCategoryRule(
        merchantKey: 'jufair marina pharmacy',
        category: 'Wife personal',
      ),
    ];
    final suggestion = kaiSuggestCashCategory('JUFAIR MARINA PHARMACY', rules)!;
    expect(suggestion.category, 'Wife personal');
    expect(suggestion.reason, 'Learned merchant rule');
  });

  test('applying learned and smart rules auto-approves only matched rows', () {
    const history = [
      KaiCashMonthRecord(
        month: '2026-07',
        income: 0,
        expenses: 0,
        transactions: [
          KaiCashTransaction(
            id: 'learned',
            date: '2026-07-01',
            source: 'My account',
            description: 'NETFLIX.COM',
            category: 'Uncategorised',
            direction: KaiCashImportDirection.expense,
            amount: 6,
          ),
          KaiCashTransaction(
            id: 'smart',
            date: '2026-07-02',
            source: 'My account',
            description: 'JUFAIR MARINA PHARMACY',
            category: 'Uncategorised',
            direction: KaiCashImportDirection.expense,
            amount: 11,
          ),
          KaiCashTransaction(
            id: 'ambiguous',
            date: '2026-07-03',
            source: 'My account',
            description: 'UNKNOWN SHOP W.L.L.',
            category: 'Uncategorised',
            direction: KaiCashImportDirection.expense,
            amount: 4,
          ),
        ],
      ),
    ];
    const rules = [
      KaiCashCategoryRule(
        merchantKey: 'netflix com',
        category: 'Subscriptions',
      ),
    ];
    final learned = kaiApplyCashRulesToHistory(history, rules);
    expect(learned.single.transactions[0].approved, isTrue);
    expect(learned.single.transactions[0].category, 'Subscriptions');
    expect(learned.single.transactions[1].approved, isFalse);

    final smart = kaiSmartAssignCashHistory(learned, rules);
    expect(smart.single.transactions[0].approved, isTrue);
    expect(smart.single.transactions[1].approved, isTrue);
    expect(smart.single.transactions[1].category, 'Health & pharmacy');
    expect(smart.single.transactions[2].approved, isFalse);
    expect(smart.single.transactions[2].category, 'Uncategorised');
    expect(smart.single.totalExpenses, 21,
        reason: 'auto-approval must never remove financial totals');
  });

  test('history sorting is deterministic and month summary reconciles', () {
    const transactions = [
      KaiCashTransaction(
        id: 'coffee',
        date: '2026-07-02',
        source: 'My account',
        description: 'Coffee',
        category: 'Dining',
        direction: KaiCashImportDirection.expense,
        amount: 3,
      ),
      KaiCashTransaction(
        id: 'salary',
        date: '2026-07-30',
        source: 'My account',
        description: 'Salary',
        category: 'Income',
        direction: KaiCashImportDirection.income,
        amount: 100,
      ),
      KaiCashTransaction(
        id: 'unknown',
        date: '2026-07-10',
        source: 'Wife account',
        description: 'Unknown shop',
        category: 'Uncategorised',
        direction: KaiCashImportDirection.expense,
        amount: 8,
      ),
    ];
    expect(
      kaiSortCashTransactions(transactions, KaiCashHistorySort.newest)
          .map((item) => item.id),
      ['salary', 'unknown', 'coffee'],
    );
    expect(
      kaiSortCashTransactions(transactions, KaiCashHistorySort.amountHigh)
          .map((item) => item.id),
      ['salary', 'unknown', 'coffee'],
    );
    final summary = kaiSummariseCashMonth(const KaiCashMonthRecord(
      month: '2026-07',
      income: 0,
      expenses: 0,
      transactions: transactions,
    ));
    expect(summary.spendingByCategory['Dining'], 3);
    expect(summary.spendingByCategory['Uncategorised'], 8);
    expect(summary.netByAccount['My account'], 97);
    expect(summary.netByAccount['Wife account'], -8);
    expect(summary.uncategorisedCount, 1);
  });

  test('approved transactions leave review queue but remain in totals', () {
    const transaction = KaiCashTransaction(
      id: 'approved-coffee',
      date: '2026-07-02',
      source: 'My account',
      description: 'Coffee',
      category: 'Dining',
      direction: KaiCashImportDirection.expense,
      amount: 3,
      approved: true,
    );
    final restored = KaiCashTransaction.fromJson(
      jsonDecode(jsonEncode(transaction.toJson())),
    )!;
    expect(restored.approved, isTrue);
    const month = KaiCashMonthRecord(
      month: '2026-07',
      income: 0,
      expenses: 0,
      transactions: [transaction],
    );
    expect(month.totalExpenses, 3);
    expect(kaiSummariseCashMonth(month).spendingByCategory['Dining'], 3);
    expect(kaiCashPendingApprovalCount([month]), 0);
    expect(
      kaiCashPendingApprovalCount([
        month.copyWith(transactions: [transaction.copyWith(approved: false)])
      ]),
      1,
    );
  });

  test('one merchant decision categorises and approves every pending match',
      () {
    const matching = KaiCashTransaction(
      id: 'eazy-1',
      date: '2026-07-31',
      source: 'My account',
      description: 'POS PURCHASE POS Pay Account - Benefit, EAZY BENEFITPAY QR',
      category: 'Uncategorised',
      direction: KaiCashImportDirection.expense,
      amount: 20.2,
    );
    const history = [
      KaiCashMonthRecord(
        month: '2026-07',
        income: 0,
        expenses: 0,
        transactions: [
          matching,
          KaiCashTransaction(
            id: 'eazy-2',
            date: '2026-07-31',
            source: 'My account',
            description:
                'POS PURCHASE POS Pay Account - Benefit, EAZY BENEFITPAY QR',
            category: 'Uncategorised',
            direction: KaiCashImportDirection.expense,
            amount: 1.5,
          ),
          KaiCashTransaction(
            id: 'reviewed',
            date: '2026-07-31',
            source: 'My account',
            description:
                'POS PURCHASE POS Pay Account - Benefit, EAZY BENEFITPAY QR',
            category: 'Business',
            direction: KaiCashImportDirection.expense,
            amount: 11.9,
          ),
          KaiCashTransaction(
            id: 'other',
            date: '2026-07-31',
            source: 'My account',
            description: 'OTHER MERCHANT',
            category: 'Uncategorised',
            direction: KaiCashImportDirection.expense,
            amount: 4,
          ),
        ],
      ),
    ];
    expect(kaiCashMatchingPendingCount(history, matching), 2);
    final result = kaiCategoriseMatchingCashTransactions(
      history: history,
      target: matching,
      category: 'Dining',
    );
    expect(result.single.transactions[0].category, 'Dining');
    expect(result.single.transactions[0].approved, isTrue);
    expect(result.single.transactions[1].category, 'Dining');
    expect(result.single.transactions[1].approved, isTrue);
    expect(result.single.transactions[2].category, 'Business');
    expect(result.single.transactions[2].approved, isFalse,
        reason: 'a previously reviewed category must remain untouched');
    expect(result.single.transactions[3].category, 'Uncategorised');
    expect(result.single.totalExpenses, 37.6);
  });

  test('approve categorised clears only reviewed rows from the queue', () {
    const month = KaiCashMonthRecord(
      month: '2026-07',
      income: 0,
      expenses: 0,
      transactions: [
        KaiCashTransaction(
          id: 'ready',
          date: '2026-07-01',
          source: 'card',
          description: 'Coffee',
          category: 'Dining',
          direction: KaiCashImportDirection.expense,
          amount: 3,
        ),
        KaiCashTransaction(
          id: 'unknown',
          date: '2026-07-02',
          source: 'card',
          description: 'Unknown',
          category: 'Uncategorised',
          direction: KaiCashImportDirection.expense,
          amount: 4,
        ),
      ],
    );
    final result = kaiApproveCategorisedCashTransactions(const [month]);
    expect(result.single.transactions.first.approved, isTrue);
    expect(result.single.transactions.last.approved, isFalse);
    expect(kaiCashPendingApprovalCount(result), 1);
    expect(result.single.totalExpenses, 7);
  });

  test('CSV statement parser handles debit, credit, quotes and duplicates', () {
    const csv = '''Date,Description,Debit,Credit,Category
12/07/2026,"Netflix, Amsterdam",6.000,,Subscriptions
28/07/2026,Salary,,4000.000,Income
12/07/2026,"Netflix, Amsterdam",6.000,,Subscriptions''';
    final rows = KaiCashStatementParser.parse(csv, source: 'bank.csv');

    expect(rows.length, 2);
    expect(rows.first.date, '2026-07-12');
    expect(rows.first.description, 'Netflix, Amsterdam');
    expect(rows.first.direction, KaiCashImportDirection.expense);
    expect(rows.first.amount, 6);
    expect(rows.last.direction, KaiCashImportDirection.income);
    expect(rows.last.amount, 4000);
  });

  test('text statement parser treats unsigned rows as spend and CR as income',
      () {
    const text = '''12/07/2026 SUPERMARKET BHD 18.250
28/07/2026 SALARY BHD 4000.000 CR''';
    final rows = KaiCashStatementParser.parse(text, source: 'statement.pdf');

    expect(rows.length, 2);
    expect(rows.first.direction, KaiCashImportDirection.expense);
    expect(rows.first.amount, 18.25);
    expect(rows.last.direction, KaiCashImportDirection.income);
  });

  test('named-month account statement parses multiline debit and credit rows',
      () {
    const text = '''Page 1 of 1
Statement of Account
Posting Date Description Value Date Amount Balance
01 JUL 2026 FT26182SMKRD 01 JUL 2026 (-) 11.550 41.066
POS PURCHASE AFS Acquiring ONUS, LOCAL PHARMACY
MANAMA BH
01 JUL 2026 FT26182WSM3P 01 JUL 2026 (+) 20.000 61.066
Internal Transfer CUSTOMER, reimbursement
This is a Computer Generated Statement.''';
    final rows =
        KaiCashStatementParser.parse(text, source: 'account-movements.pdf');

    expect(rows, hasLength(2));
    expect(rows.first.date, '2026-07-01');
    expect(rows.first.direction, KaiCashImportDirection.expense);
    expect(rows.first.amount, 11.55);
    expect(rows.first.description, contains('LOCAL PHARMACY'));
    expect(rows.last.direction, KaiCashImportDirection.income);
    expect(rows.last.amount, 20);
    expect(rows.last.description, 'Internal Transfer CUSTOMER, reimbursement');
  });

  test('column-ordered PDF text preserves repeated rows by bank reference', () {
    const text = '''01 JUL 2026
01 JUL 2026
FT26182AAAA
LOCAL MERCHANT
(-) 1.500
50.000
01 JUL 2026
01 JUL 2026
FT26182BBBB
LOCAL MERCHANT
(-) 1.500
48.500
31 JUL 2026
31 JUL 2026
693594150000-12345678
CLOSING CREDIT
(+) 2.000
50.500''';
    final rows =
        KaiCashStatementParser.parse(text, source: 'account-movements.pdf');

    expect(rows, hasLength(3));
    expect(rows.take(2).map((row) => row.amount), everyElement(1.5));
    expect(rows.last.direction, KaiCashImportDirection.income);
    expect(rows.last.date, '2026-07-31');
  });

  test('text-based PDF statement extracts locally into review candidates',
      () async {
    final document = PdfDocument();
    document.pages.add().graphics.drawString(
          '12/07/2026 SUPERMARKET BHD 18.250',
          PdfStandardFont(PdfFontFamily.helvetica, 12),
        );
    final bytes = await document.save();
    document.dispose();

    final text = KaiCashStatementParser.extractPdfText(bytes);
    final rows = KaiCashStatementParser.parse(text, source: 'statement.pdf');
    expect(rows, hasLength(1));
    expect(rows.single.description, 'SUPERMARKET');
    expect(rows.single.amount, 18.25);
    expect(rows.single.direction, KaiCashImportDirection.expense);
  });

  test('reviewed statement merge is idempotent across repeated imports', () {
    const candidate = KaiCashImportCandidate(
      date: '2026-07-12',
      description: 'Netflix',
      amount: 6,
      direction: KaiCashImportDirection.expense,
      source: 'card.csv',
      category: 'Subscriptions & memberships',
      subcategory: 'Netflix',
    );
    var sequence = 0;
    final first = kaiMergeStatementCandidates(
      history: const [],
      candidates: const [candidate],
      nextId: () => 'row-${sequence++}',
    );
    final second = kaiMergeStatementCandidates(
      history: first.history,
      candidates: const [candidate],
      nextId: () => 'row-${sequence++}',
    );

    expect(first.imported, 1);
    expect(second.imported, 0);
    expect(second.duplicates, 1);
    expect(second.history.single.transactions, hasLength(1));
  });

  test('weekly and yearly entries normalize to a monthly figure', () {
    const weekly = KaiCashFlowLine(
      id: 'weekly',
      label: 'Weekly',
      amount: 120,
      cadence: KaiCashCadence.weekly,
    );
    const yearly = KaiCashFlowLine(
      id: 'yearly',
      label: 'Yearly',
      amount: 1200,
      cadence: KaiCashCadence.yearly,
    );

    expect(weekly.monthlyAmount, closeTo(520, 0.0001));
    expect(yearly.monthlyAmount, 100);
  });

  test('desktop uses a wide cash dock with a compact narrow fallback', () {
    final shell = File('lib/screens/kai_desktop_shell.dart').readAsStringSync();
    final projectsPanel = shell.substring(
      shell.indexOf('Widget _projectsPanel()'),
      shell.indexOf('Widget _desktopWorkQueueCard()'),
    );

    expect(projectsPanel.split('KaiPersonalCashCard').length - 1, 1);
    expect(projectsPanel, contains('screenWidth < 1690'));
    expect(shell.split('KaiPersonalCashDock').length - 1, 1);
    expect(shell, contains('constraints.maxWidth < 980'));
    expect(shell, contains("import '../widgets/kai_personal_cash_card.dart';"));
  });

  testWidgets('wide dock uses dashboard colors and fills its available panel',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(455, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF070B12),
          body: Padding(
            padding: EdgeInsets.all(8),
            child: KaiPersonalCashDock(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('personal-cash-dock')), findsOneWidget);
    expect(find.text('PERSONAL CASH'), findsOneWidget);
    expect(find.text('INCOME SOURCES'), findsOneWidget);
    expect(find.text('DEBTS + PAYABLES'), findsOneWidget);
    expect(find.text('Moon plaza'), findsOneWidget);
    expect(find.text('Credimax'), findsOneWidget);
    expect(find.textContaining('no Firebase'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('highlighted card expands into the full local-only breakdown',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF070B12),
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 380, child: KaiPersonalCashCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PERSONAL CASH'), findsOneWidget);
    expect(find.text('BD 4,995'), findsOneWidget);
    expect(find.text('BD +3,975'), findsOneWidget);

    await tester.tap(find.byKey(const Key('personal-cash-card')));
    await tester.pumpAndSettle();

    expect(find.text('Personal cash breakdown'), findsOneWidget);
    expect(find.text('Income sources'), findsOneWidget);
    expect(find.text('Expense categories'), findsOneWidget);
    expect(find.text('Debts and payables'), findsOneWidget);
    expect(find.text('Savings & investments'), findsOneWidget);
    expect(find.text('Add savings or investment'), findsOneWidget);
    expect(find.byTooltip('Add subcategory'), findsNWidgets(2));
    expect(find.text('Receivables'), findsOneWidget);
    expect(find.text('Import statement'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cash-tab-4')));
    await tester.pumpAndSettle();
    expect(find.text('Recognised accounts'), findsOneWidget);
    expect(find.byKey(const Key('cash-add-account')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cash-add-account')));
    await tester.pumpAndSettle();
    expect(find.text('Matching clues, separated by commas'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'the account identity editor must fit without overflow');

    await tester.tap(find.byKey(const Key('cash-tab-2')));
    await tester.pumpAndSettle();
    expect(find.text('Monthly history + patterns'), findsOneWidget);
    expect(find.byKey(const Key('cash-history-chart')), findsOneWidget);
    expect(find.byKey(const Key('cash-history-sort')), findsOneWidget);
    expect(find.text('SORT'), findsOneWidget);
    expect(find.byKey(const Key('cash-smart-category-assign')), findsOneWidget);
    expect(
        find.byKey(const Key('cash-approve-all-categorised')), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cash-history-sort')));
    await tester.pumpAndSettle();
    expect(find.text('Largest amount'), findsOneWidget);
    await tester.tap(find.text('Largest amount'));
    await tester.pumpAndSettle();
    expect(find.text('Largest'), findsOneWidget);
    expect(find.byKey(const Key('cash-history-uncategorised-filter')),
        findsOneWidget);
    expect(find.byKey(const Key('cash-history-show-approved')), findsOneWidget);
    expect(
        find.byKey(const Key('cash-pending-approval-count')), findsOneWidget);
    expect(find.text('All approved'), findsOneWidget);
    expect(find.text('Add historical month'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cash-tab-1')));
    await tester.pumpAndSettle();
    expect(find.text('Expected receivables'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cash-tab-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cash-upload-statement')), findsOneWidget);
    expect(find.byKey(const Key('cash-import-add-category')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cash-import-add-category')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('cash-new-category-name')), 'Dining out');
    await tester.tap(find.byKey(const Key('cash-save-new-category')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'adding a reusable category must not overflow');

    await tester.tap(find.byKey(const Key('cash-tab-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add historical month'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the editable historical month header must fit');
    await tester.tap(find.text('Add transaction'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cash-month-summary-2026-08')), findsOneWidget);
    expect(find.text('1 left to approve'), findsOneWidget);
    expect(find.text('1 TO APPROVE'), findsOneWidget);
    expect(
        find.byTooltip('Approve and remove from review list'), findsOneWidget);
    await tester.tap(find.byTooltip('Approve and remove from review list'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Approve and remove from review list'), findsNothing);
    expect(find.text('All approved'), findsOneWidget);
    expect(find.text('ALL APPROVED'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cash-history-show-approved')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mark as needing review'), findsOneWidget);
    final transactionLayoutError = tester.takeException();
    expect(transactionLayoutError, isNull,
        reason: 'the editable historical transaction row must fit');
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'the reusable category menu must fit');
    expect(find.text('Dining out'), findsOneWidget);
    await tester.tap(find.text('Dining out'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No Firebase'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
