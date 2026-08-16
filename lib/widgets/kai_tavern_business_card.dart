import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tavernCyan = Color(0xFF27D7F2);
const _tavernAmber = Color(0xFFFFB43B);
const _tavernGreen = Color(0xFF70E58A);
const _tavernRed = Color(0xFFFF6678);
const _tavernPanel = Color(0xFF07131E);

enum KaiTavernChartMetric { netSales, netProfit, cash, customers }

extension KaiTavernChartMetricView on KaiTavernChartMetric {
  String get label => switch (this) {
        KaiTavernChartMetric.netSales => 'Net sales',
        KaiTavernChartMetric.netProfit => 'Net profit',
        KaiTavernChartMetric.cash => 'Cash',
        KaiTavernChartMetric.customers => 'Customers',
      };

  Color get color => switch (this) {
        KaiTavernChartMetric.netSales => _tavernCyan,
        KaiTavernChartMetric.netProfit => _tavernGreen,
        KaiTavernChartMetric.cash => _tavernAmber,
        KaiTavernChartMetric.customers => const Color(0xFFC8B5FF),
      };
}

class KaiTavernPeriod {
  const KaiTavernPeriod({
    required this.period,
    this.grossSales = 0,
    this.discounts = 0,
    this.refunds = 0,
    this.cogs = 0,
    this.labor = 0,
    this.rent = 0,
    this.utilities = 0,
    this.marketing = 0,
    this.deliveryFees = 0,
    this.otherExpenses = 0,
    this.taxes = 0,
    this.cash = 0,
    this.receivables = 0,
    this.payables = 0,
    this.inventory = 0,
    this.orders = 0,
    this.customers = 0,
    this.newCustomers = 0,
    this.repeatCustomers = 0,
    this.covers = 0,
    this.capacityCovers = 0,
    this.openingDays = 0,
    this.sourceNote = '',
  });

  final String period;
  final double grossSales;
  final double discounts;
  final double refunds;
  final double cogs;
  final double labor;
  final double rent;
  final double utilities;
  final double marketing;
  final double deliveryFees;
  final double otherExpenses;
  final double taxes;
  final double cash;
  final double receivables;
  final double payables;
  final double inventory;
  final int orders;
  final int customers;
  final int newCustomers;
  final int repeatCustomers;
  final int covers;
  final int capacityCovers;
  final int openingDays;
  final String sourceNote;

  double get netSales => math.max(0, grossSales - discounts - refunds);
  double get grossProfit => netSales - cogs;
  double get operatingExpenses =>
      labor + rent + utilities + marketing + deliveryFees + otherExpenses;
  double get operatingProfit => grossProfit - operatingExpenses;
  double get netProfit => operatingProfit - taxes;
  double get grossMargin => netSales == 0 ? 0 : grossProfit / netSales;
  double get netMargin => netSales == 0 ? 0 : netProfit / netSales;
  double get averageOrderValue => orders == 0 ? 0 : netSales / orders;
  double get revenuePerCustomer => customers == 0 ? 0 : netSales / customers;
  double get laborRatio => netSales == 0 ? 0 : labor / netSales;
  double get cogsRatio => netSales == 0 ? 0 : cogs / netSales;
  double get repeatRate => customers == 0 ? 0 : repeatCustomers / customers;
  double get occupancy => capacityCovers <= 0 || openingDays <= 0
      ? 0
      : (covers / (capacityCovers * openingDays)).clamp(0, 1).toDouble();
  double get workingCapital => cash + receivables + inventory - payables;
  double get breakEvenSales {
    if (netSales <= 0) return 0;
    final contribution =
        ((netSales - cogs - deliveryFees) / netSales).clamp(0, 1).toDouble();
    if (contribution <= 0) return 0;
    return (labor + rent + utilities + marketing + otherExpenses) /
        contribution;
  }

  double valueOf(KaiTavernChartMetric metric) => switch (metric) {
        KaiTavernChartMetric.netSales => netSales,
        KaiTavernChartMetric.netProfit => netProfit,
        KaiTavernChartMetric.cash => cash,
        KaiTavernChartMetric.customers => customers.toDouble(),
      };

  Map<String, Object> toJson() => {
        'period': period,
        'grossSales': grossSales,
        'discounts': discounts,
        'refunds': refunds,
        'cogs': cogs,
        'labor': labor,
        'rent': rent,
        'utilities': utilities,
        'marketing': marketing,
        'deliveryFees': deliveryFees,
        'otherExpenses': otherExpenses,
        'taxes': taxes,
        'cash': cash,
        'receivables': receivables,
        'payables': payables,
        'inventory': inventory,
        'orders': orders,
        'customers': customers,
        'newCustomers': newCustomers,
        'repeatCustomers': repeatCustomers,
        'covers': covers,
        'capacityCovers': capacityCovers,
        'openingDays': openingDays,
        'sourceNote': sourceNote,
      };

  static KaiTavernPeriod? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final period = raw['period']?.toString() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(period)) return null;
    double number(String key) => (raw[key] as num?)?.toDouble() ?? 0;
    int count(String key) => (raw[key] as num?)?.toInt() ?? 0;
    return KaiTavernPeriod(
      period: period,
      grossSales: number('grossSales'),
      discounts: number('discounts'),
      refunds: number('refunds'),
      cogs: number('cogs'),
      labor: number('labor'),
      rent: number('rent'),
      utilities: number('utilities'),
      marketing: number('marketing'),
      deliveryFees: number('deliveryFees'),
      otherExpenses: number('otherExpenses'),
      taxes: number('taxes'),
      cash: number('cash'),
      receivables: number('receivables'),
      payables: number('payables'),
      inventory: number('inventory'),
      orders: count('orders'),
      customers: count('customers'),
      newCustomers: count('newCustomers'),
      repeatCustomers: count('repeatCustomers'),
      covers: count('covers'),
      capacityCovers: count('capacityCovers'),
      openingDays: count('openingDays'),
      sourceNote: raw['sourceNote']?.toString() ?? '',
    );
  }
}

class KaiTavernBusinessSnapshot {
  const KaiTavernBusinessSnapshot({
    this.periods = const [],
    this.revenueTarget = 0,
    this.profitTarget = 0,
    this.cashBufferTarget = 0,
    this.goalDate = '',
  });

  final List<KaiTavernPeriod> periods;
  final double revenueTarget;
  final double profitTarget;
  final double cashBufferTarget;
  final String goalDate;

  KaiTavernPeriod? get latest {
    if (periods.isEmpty) return null;
    final sorted = [...periods]..sort((a, b) => a.period.compareTo(b.period));
    return sorted.last;
  }

  KaiTavernBusinessSnapshot copyWith({
    List<KaiTavernPeriod>? periods,
    double? revenueTarget,
    double? profitTarget,
    double? cashBufferTarget,
    String? goalDate,
  }) =>
      KaiTavernBusinessSnapshot(
        periods: periods ?? this.periods,
        revenueTarget: revenueTarget ?? this.revenueTarget,
        profitTarget: profitTarget ?? this.profitTarget,
        cashBufferTarget: cashBufferTarget ?? this.cashBufferTarget,
        goalDate: goalDate ?? this.goalDate,
      );

  Map<String, Object> toJson() => {
        'version': 1,
        'periods': periods.map((item) => item.toJson()).toList(),
        'revenueTarget': revenueTarget,
        'profitTarget': profitTarget,
        'cashBufferTarget': cashBufferTarget,
        'goalDate': goalDate,
      };

  static KaiTavernBusinessSnapshot? fromJson(Object? raw) {
    if (raw is! Map || raw['version'] != 1) return null;
    final periods = raw['periods'] is List
        ? (raw['periods'] as List)
            .map(KaiTavernPeriod.fromJson)
            .whereType<KaiTavernPeriod>()
            .toList()
        : <KaiTavernPeriod>[];
    periods.sort((a, b) => a.period.compareTo(b.period));
    return KaiTavernBusinessSnapshot(
      periods: periods,
      revenueTarget: (raw['revenueTarget'] as num?)?.toDouble() ?? 0,
      profitTarget: (raw['profitTarget'] as num?)?.toDouble() ?? 0,
      cashBufferTarget: (raw['cashBufferTarget'] as num?)?.toDouble() ?? 0,
      goalDate: raw['goalDate']?.toString() ?? '',
    );
  }
}

class KaiTavernBusinessStore {
  KaiTavernBusinessStore._();
  static final instance = KaiTavernBusinessStore._();
  static const key = 'kai_tavern_business_tracker_v1';

  Future<KaiTavernBusinessSnapshot> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return const KaiTavernBusinessSnapshot();
    try {
      return KaiTavernBusinessSnapshot.fromJson(jsonDecode(raw)) ??
          const KaiTavernBusinessSnapshot();
    } catch (_) {
      return const KaiTavernBusinessSnapshot();
    }
  }

  Future<void> save(KaiTavernBusinessSnapshot value) async =>
      (await SharedPreferences.getInstance())
          .setString(key, jsonEncode(value.toJson()));
}

class KaiTavernBusinessCard extends StatefulWidget {
  const KaiTavernBusinessCard({super.key});
  @override
  State<KaiTavernBusinessCard> createState() => _KaiTavernBusinessCardState();
}

class _KaiTavernBusinessCardState extends State<KaiTavernBusinessCard> {
  KaiTavernBusinessSnapshot _value = const KaiTavernBusinessSnapshot();
  KaiTavernChartMetric _metric = KaiTavernChartMetric.netSales;

  @override
  void initState() {
    super.initState();
    KaiTavernBusinessStore.instance.load().then((value) {
      if (mounted) setState(() => _value = value);
    });
  }

  Future<void> _edit() async {
    final updated = await showDialog<KaiTavernBusinessSnapshot>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.78),
      builder: (_) => _KaiTavernBusinessDialog(initial: _value),
    );
    if (updated != null && mounted) setState(() => _value = updated);
  }

  @override
  Widget build(BuildContext context) {
    final latest = _value.latest;
    return Container(
      key: const Key('tavern-business-card'),
      decoration: BoxDecoration(
        color: _tavernPanel.withOpacity(0.91),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _tavernCyan.withOpacity(0.38)),
        boxShadow: [
          BoxShadow(color: _tavernCyan.withOpacity(0.06), blurRadius: 20)
        ],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 10, 5),
          child: Row(children: [
            const Icon(Icons.storefront_outlined, color: _tavernCyan, size: 18),
            const SizedBox(width: 9),
            const Expanded(
                child: Text('TAVERN',
                    style: TextStyle(
                        color: Color(0xFFDCEAF4),
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontFamily: 'monospace'))),
            Text(latest?.period ?? 'NO PERIOD',
                style: const TextStyle(
                    color: Color(0xFF7890A2),
                    fontSize: 7.5,
                    fontFamily: 'monospace')),
            TextButton(
              key: const Key('tavern-edit'),
              onPressed: _edit,
              child: const Text('EDIT',
                  style: TextStyle(
                      color: _tavernCyan,
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            children: [
              _hero(latest),
              const SizedBox(height: 7),
              _tabs(),
              const SizedBox(height: 5),
              SizedBox(
                height: 58,
                child: CustomPaint(
                  key: const Key('tavern-history-chart'),
                  painter: _TavernChartPainter(
                    values: _value.periods
                        .map((item) => item.valueOf(_metric))
                        .toList(),
                    target: _targetFor(_metric),
                    color: _metric.color,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                latest == null
                    ? 'LOCAL MANUAL TRACKER  ·  NO BUSINESS FIGURES ENTERED'
                    : 'MANUAL · LOCAL · UNVERIFIED  ·  ${latest.sourceNote.isEmpty ? 'no source note' : latest.sourceNote}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFF6F8798),
                    fontSize: 7.5,
                    letterSpacing: 0.35,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  double _targetFor(KaiTavernChartMetric metric) => switch (metric) {
        KaiTavernChartMetric.netSales => _value.revenueTarget,
        KaiTavernChartMetric.netProfit => _value.profitTarget,
        KaiTavernChartMetric.cash => _value.cashBufferTarget,
        KaiTavernChartMetric.customers => 0,
      };

  Widget _hero(KaiTavernPeriod? item) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xFF0B1A26).withOpacity(0.88),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _tavernCyan.withOpacity(0.16))),
        child: Column(children: [
          Row(children: [
            _metricCell('NET SALES', _bd(item?.netSales), _tavernCyan),
            _metricCell('NET PROFIT', _bd(item?.netProfit),
                (item?.netProfit ?? 0) >= 0 ? _tavernGreen : _tavernRed),
            _metricCell('CASH', _bd(item?.cash), _tavernAmber),
            _metricCell('PAYABLES', _bd(item?.payables), Colors.white),
          ]),
          const SizedBox(height: 7),
          Row(children: [
            _smallCell('MARGIN', _percent(item?.netMargin)),
            _smallCell('AOV', _bd(item?.averageOrderValue)),
            _smallCell('ORDERS', item == null ? '--' : '${item.orders}'),
            _smallCell('CUSTOMERS', item == null ? '--' : '${item.customers}'),
          ]),
        ]),
      );

  Widget _metricCell(String label, String value, Color color) => Expanded(
        child: Column(children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w900)),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF71899A),
                  fontSize: 6.2,
                  fontFamily: 'monospace')),
        ]),
      );

  Widget _smallCell(String label, String value) => Expanded(
        child: Text('$label  $value',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Color(0xFF9FB6C8),
                fontSize: 7.2,
                fontFamily: 'monospace')),
      );

  Widget _tabs() => Row(
          children: KaiTavernChartMetric.values.map((metric) {
        final selected = metric == _metric;
        return Expanded(
          child: InkWell(
            key: Key('tavern-metric-${metric.name}'),
            onTap: () => setState(() => _metric = metric),
            borderRadius: BorderRadius.circular(7),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                  color: selected
                      ? metric.color.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                      color: selected
                          ? metric.color.withOpacity(0.45)
                          : Colors.white.withOpacity(0.06))),
              child: Text(metric.label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected ? metric.color : const Color(0xFF71899A),
                      fontSize: 7.2,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        );
      }).toList());
}

class _KaiTavernBusinessDialog extends StatefulWidget {
  const _KaiTavernBusinessDialog({required this.initial});
  final KaiTavernBusinessSnapshot initial;
  @override
  State<_KaiTavernBusinessDialog> createState() =>
      _KaiTavernBusinessDialogState();
}

class _KaiTavernBusinessDialogState extends State<_KaiTavernBusinessDialog> {
  late KaiTavernBusinessSnapshot _value = widget.initial;
  final Map<String, TextEditingController> _fields = {};
  late final TextEditingController _revenueTarget;
  late final TextEditingController _profitTarget;
  late final TextEditingController _cashTarget;
  late final TextEditingController _goalDate;

  static const _moneyFields = <String, String>{
    'grossSales': 'Gross sales (BD)',
    'discounts': 'Discounts (BD)',
    'refunds': 'Refunds (BD)',
    'cogs': 'Food / COGS (BD)',
    'labor': 'Labor + payroll (BD)',
    'rent': 'Rent (BD)',
    'utilities': 'Utilities (BD)',
    'marketing': 'Marketing (BD)',
    'deliveryFees': 'Delivery/platform fees (BD)',
    'otherExpenses': 'Other operating costs (BD)',
    'taxes': 'Tax / VAT provision (BD)',
    'cash': 'Cash available (BD)',
    'receivables': 'Receivables (BD)',
    'payables': 'Payables (BD)',
    'inventory': 'Inventory value (BD)',
  };

  static const _countFields = <String, String>{
    'orders': 'Orders / transactions',
    'customers': 'Unique customers',
    'newCustomers': 'New customers',
    'repeatCustomers': 'Repeat customers',
    'covers': 'Covers served',
    'capacityCovers': 'Daily cover capacity',
    'openingDays': 'Opening days',
  };

  @override
  void initState() {
    super.initState();
    final latest = _value.latest;
    String month = DateTime.now().toIso8601String().substring(0, 7);
    _fields['period'] = TextEditingController(text: latest?.period ?? month);
    for (final key in _moneyFields.keys) {
      _fields[key] = TextEditingController(text: _moneyValue(latest, key));
    }
    for (final key in _countFields.keys) {
      _fields[key] = TextEditingController(text: _countValue(latest, key));
    }
    _fields['sourceNote'] =
        TextEditingController(text: latest?.sourceNote ?? '');
    _revenueTarget = TextEditingController(
        text: _value.revenueTarget == 0 ? '' : '${_value.revenueTarget}');
    _profitTarget = TextEditingController(
        text: _value.profitTarget == 0 ? '' : '${_value.profitTarget}');
    _cashTarget = TextEditingController(
        text: _value.cashBufferTarget == 0 ? '' : '${_value.cashBufferTarget}');
    _goalDate = TextEditingController(text: _value.goalDate);
  }

  String _moneyValue(KaiTavernPeriod? item, String key) {
    if (item == null) return '';
    final value = switch (key) {
      'grossSales' => item.grossSales,
      'discounts' => item.discounts,
      'refunds' => item.refunds,
      'cogs' => item.cogs,
      'labor' => item.labor,
      'rent' => item.rent,
      'utilities' => item.utilities,
      'marketing' => item.marketing,
      'deliveryFees' => item.deliveryFees,
      'otherExpenses' => item.otherExpenses,
      'taxes' => item.taxes,
      'cash' => item.cash,
      'receivables' => item.receivables,
      'payables' => item.payables,
      'inventory' => item.inventory,
      _ => 0.0,
    };
    return value == 0 ? '' : '$value';
  }

  String _countValue(KaiTavernPeriod? item, String key) {
    if (item == null) return '';
    final value = switch (key) {
      'orders' => item.orders,
      'customers' => item.customers,
      'newCustomers' => item.newCustomers,
      'repeatCustomers' => item.repeatCustomers,
      'covers' => item.covers,
      'capacityCovers' => item.capacityCovers,
      'openingDays' => item.openingDays,
      _ => 0,
    };
    return value == 0 ? '' : '$value';
  }

  double _number(String key) =>
      math.max(0, double.tryParse(_fields[key]?.text.trim() ?? '') ?? 0);
  int _count(String key) =>
      math.max(0, int.tryParse(_fields[key]?.text.trim() ?? '') ?? 0);

  void _savePeriod() {
    final period = _fields['period']!.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(period)) return;
    final item = KaiTavernPeriod(
      period: period,
      grossSales: _number('grossSales'),
      discounts: _number('discounts'),
      refunds: _number('refunds'),
      cogs: _number('cogs'),
      labor: _number('labor'),
      rent: _number('rent'),
      utilities: _number('utilities'),
      marketing: _number('marketing'),
      deliveryFees: _number('deliveryFees'),
      otherExpenses: _number('otherExpenses'),
      taxes: _number('taxes'),
      cash: _number('cash'),
      receivables: _number('receivables'),
      payables: _number('payables'),
      inventory: _number('inventory'),
      orders: _count('orders'),
      customers: _count('customers'),
      newCustomers: _count('newCustomers'),
      repeatCustomers: _count('repeatCustomers'),
      covers: _count('covers'),
      capacityCovers: _count('capacityCovers'),
      openingDays: _count('openingDays'),
      sourceNote: _fields['sourceNote']!.text.trim(),
    );
    final periods = [
      ..._value.periods.where((entry) => entry.period != period),
      item,
    ]..sort((a, b) => a.period.compareTo(b.period));
    _update(_value.copyWith(periods: periods));
  }

  void _saveGoals() => _update(_value.copyWith(
        revenueTarget: math.max(0, double.tryParse(_revenueTarget.text) ?? 0),
        profitTarget: math.max(0, double.tryParse(_profitTarget.text) ?? 0),
        cashBufferTarget: math.max(0, double.tryParse(_cashTarget.text) ?? 0),
        goalDate: _goalDate.text.trim(),
      ));

  void _update(KaiTavernBusinessSnapshot value) {
    setState(() => _value = value);
    unawaited(KaiTavernBusinessStore.instance.save(value));
  }

  @override
  void dispose() {
    for (final controller in [
      ..._fields.values,
      _revenueTarget,
      _profitTarget,
      _cashTarget,
      _goalDate,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 880),
          child: Container(
            decoration: BoxDecoration(
                color: const Color(0xFF07111C),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _tavernCyan.withOpacity(0.45))),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
                child: Row(children: [
                  const Icon(Icons.storefront_outlined, color: _tavernCyan),
                  const SizedBox(width: 10),
                  const Expanded(
                      child: Text('Tavern business tracker',
                          style: TextStyle(
                              color: Color(0xFFDCEAF4),
                              fontSize: 17,
                              fontWeight: FontWeight.w800))),
                  TextButton(
                      key: const Key('tavern-dialog-done'),
                      onPressed: () => Navigator.pop(context, _value),
                      child: const Text('DONE',
                          style: TextStyle(color: _tavernCyan))),
                ]),
              ),
              Expanded(
                child: ListView(
                  key: const Key('tavern-edit-scroll'),
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  children: [
                    _section('REPORTING PERIOD + SOURCE', [
                      _field('period', 'Month (YYYY-MM)', width: 230),
                      _field('sourceNote',
                          'Source note / ledger / report reference',
                          width: 650),
                    ]),
                    _section('SALES + DEDUCTIONS', [
                      for (final key in ['grossSales', 'discounts', 'refunds'])
                        _field(key, _moneyFields[key]!),
                    ]),
                    _section('COSTS + PROFIT DRIVERS', [
                      for (final key in [
                        'cogs',
                        'labor',
                        'rent',
                        'utilities',
                        'marketing',
                        'deliveryFees',
                        'otherExpenses',
                        'taxes'
                      ])
                        _field(key, _moneyFields[key]!),
                    ]),
                    _section('CASH + BALANCE SHEET', [
                      for (final key in [
                        'cash',
                        'receivables',
                        'payables',
                        'inventory'
                      ])
                        _field(key, _moneyFields[key]!),
                    ]),
                    _section('CUSTOMERS + OPERATIONS', [
                      for (final entry in _countFields.entries)
                        _field(entry.key, entry.value),
                    ]),
                    FilledButton.icon(
                      key: const Key('tavern-save-period'),
                      onPressed: _savePeriod,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save or replace this month'),
                    ),
                    _goals(),
                    _derived(),
                    _history(),
                    const SizedBox(height: 10),
                    const Text(
                      'LOCAL MANUAL RECORD · figures remain UNVERIFIED until reconciled to the named ledger or report. No Firebase or bank connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFF71899A),
                          fontSize: 9,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );

  Widget _field(String key, String label, {double width = 210}) => SizedBox(
        width: width,
        child: TextField(
          key: Key('tavern-field-$key'),
          controller: _fields[key],
          keyboardType: key == 'period' || key == 'sourceNote'
              ? TextInputType.text
              : const TextInputType.numberWithOptions(decimal: true),
          decoration: _decoration(label),
        ),
      );

  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFF0B1824),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: _tavernCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  fontFamily: 'monospace')),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: children),
        ]),
      );

  Widget _goals() => _section('TARGETS + DATE', [
        SizedBox(
            width: 210,
            child: TextField(
                key: const Key('tavern-revenue-target'),
                controller: _revenueTarget,
                keyboardType: TextInputType.number,
                decoration: _decoration('Monthly net sales target (BD)'))),
        SizedBox(
            width: 210,
            child: TextField(
                key: const Key('tavern-profit-target'),
                controller: _profitTarget,
                keyboardType: TextInputType.number,
                decoration: _decoration('Monthly net profit target (BD)'))),
        SizedBox(
            width: 210,
            child: TextField(
                key: const Key('tavern-cash-target'),
                controller: _cashTarget,
                keyboardType: TextInputType.number,
                decoration: _decoration('Cash buffer target (BD)'))),
        SizedBox(
            width: 210,
            child: TextField(
                key: const Key('tavern-goal-date'),
                controller: _goalDate,
                decoration: _decoration('Target date YYYY-MM-DD'))),
        OutlinedButton.icon(
            onPressed: _saveGoals,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Save targets')),
      ]);

  Widget _derived() {
    final item = _value.latest;
    if (item == null) {
      return _section('AUTOMATIC BUSINESS METRICS', [
        const Text(
            'Save a reporting month to calculate margins and break-even.',
            style: TextStyle(color: Color(0xFF9FB6C8)))
      ]);
    }
    final metrics = <String, String>{
      'Net sales': _bd(item.netSales),
      'Gross profit': _bd(item.grossProfit),
      'Operating profit': _bd(item.operatingProfit),
      'Net profit': _bd(item.netProfit),
      'Gross margin': _percent(item.grossMargin),
      'Net margin': _percent(item.netMargin),
      'Break-even sales': _bd(item.breakEvenSales),
      'Average order': _bd(item.averageOrderValue),
      'Revenue/customer': _bd(item.revenuePerCustomer),
      'Labor %': _percent(item.laborRatio),
      'COGS %': _percent(item.cogsRatio),
      'Repeat rate': _percent(item.repeatRate),
      'Capacity use': _percent(item.occupancy),
      'Working capital': _bd(item.workingCapital),
    };
    return _section('AUTOMATIC BUSINESS METRICS', [
      for (final entry in metrics.entries)
        SizedBox(
          width: 180,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.value,
                style: const TextStyle(
                    color: Color(0xFFDCEAF4), fontWeight: FontWeight.w800)),
            Text(entry.key,
                style: const TextStyle(color: Color(0xFF71899A), fontSize: 9)),
          ]),
        )
    ]);
  }

  Widget _history() => _section('MONTHLY HISTORY', [
        if (_value.periods.isEmpty)
          const Text('No reporting periods saved.',
              style: TextStyle(color: Color(0xFF71899A)))
        else
          for (final item in _value.periods.reversed)
            Container(
              width: 1000,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.025),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                SizedBox(
                    width: 90,
                    child: Text(item.period,
                        style: const TextStyle(color: _tavernCyan))),
                Expanded(child: Text('Sales ${_bd(item.netSales)}')),
                Expanded(child: Text('Profit ${_bd(item.netProfit)}')),
                Expanded(child: Text('Cash ${_bd(item.cash)}')),
                IconButton(
                    tooltip: 'Delete ${item.period}',
                    onPressed: () => _update(_value.copyWith(
                        periods: _value.periods
                            .where((entry) => entry.period != item.period)
                            .toList())),
                    icon: const Icon(Icons.delete_outline,
                        color: Color(0xFFFF6678), size: 18)),
              ]),
            ),
      ]);

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF91A8BA), fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF101E2A),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: _tavernCyan)),
      );
}

class _TavernChartPainter extends CustomPainter {
  const _TavernChartPainter(
      {required this.values, required this.target, required this.color});
  final List<double> values;
  final double target;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) {
      final painter = TextPainter(
          text: const TextSpan(
              text: 'Add monthly figures to build the trend',
              style: TextStyle(color: Color(0xFF60798A), fontSize: 9)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width);
      painter.paint(canvas,
          Offset((size.width - painter.width) / 2, size.height / 2 - 6));
      return;
    }
    final all = [...values, if (target > 0) target];
    var minValue = all.reduce(math.min);
    var maxValue = all.reduce(math.max);
    if (minValue == maxValue) {
      minValue -= 1;
      maxValue += 1;
    }
    double y(double value) =>
        size.height -
        ((value - minValue) / (maxValue - minValue)) * size.height;
    if (target > 0) {
      canvas.drawLine(Offset(0, y(target)), Offset(size.width, y(target)),
          Paint()..color = _tavernAmber.withOpacity(0.55));
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final point = Offset(x, y(values[i]));
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
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _TavernChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.target != target ||
      oldDelegate.color != color;
}

String _bd(double? value) => value == null ? '--' : 'BD ${_money(value)}';
String _percent(double? value) =>
    value == null ? '--' : '${(value * 100).toStringAsFixed(1)}%';
String _money(double value) {
  final negative = value < 0;
  final absolute = value.abs();
  final fixed = absolute.toStringAsFixed(absolute % 1 == 0 ? 0 : 2);
  final parts = fixed.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  if (parts.length > 1) buffer.write('.${parts.last}');
  return '${negative ? '-' : ''}$buffer';
}
