import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/core/kai_whoop_service.dart';

const _cyan = Color(0xFF2ED9FF);
const _green = Color(0xFF7EE787);
const _amber = Color(0xFFFFB84D);
const _panel = Color(0xFF08131D);

enum KaiBodyMetric { weight, waist, rhr, leanMass }

extension KaiBodyMetricLabel on KaiBodyMetric {
  String get label => switch (this) {
        KaiBodyMetric.weight => 'Weight',
        KaiBodyMetric.waist => 'Waist',
        KaiBodyMetric.rhr => 'RHR',
        KaiBodyMetric.leanMass => 'Lean mass',
      };
  String get unit => switch (this) {
        KaiBodyMetric.weight || KaiBodyMetric.leanMass => 'kg',
        KaiBodyMetric.waist => 'cm',
        KaiBodyMetric.rhr => 'bpm',
      };
  Color get color => switch (this) {
        KaiBodyMetric.weight => _cyan,
        KaiBodyMetric.waist => _amber,
        KaiBodyMetric.rhr => const Color(0xFFFF6B78),
        KaiBodyMetric.leanMass => _green,
      };
}

class KaiBodyMeasurement {
  const KaiBodyMeasurement({
    required this.date,
    this.weight,
    this.waist,
    this.rhr,
    this.leanMass,
    this.source = 'manual',
  });
  final String date;
  final double? weight;
  final double? waist;
  final double? rhr;
  final double? leanMass;
  final String source;

  double? valueOf(KaiBodyMetric metric) => switch (metric) {
        KaiBodyMetric.weight => weight,
        KaiBodyMetric.waist => waist,
        KaiBodyMetric.rhr => rhr,
        KaiBodyMetric.leanMass => leanMass,
      };

  Map<String, Object?> toJson() => {
        'date': date,
        'weight': weight,
        'waist': waist,
        'rhr': rhr,
        'leanMass': leanMass,
        'source': source,
      };

  static KaiBodyMeasurement? fromJson(Object? raw) {
    if (raw is! Map || (raw['date']?.toString() ?? '').isEmpty) return null;
    double? number(Object? value) => value is num ? value.toDouble() : null;
    return KaiBodyMeasurement(
      date: raw['date'].toString(),
      weight: number(raw['weight']),
      waist: number(raw['waist']),
      rhr: number(raw['rhr']),
      leanMass: number(raw['leanMass']),
      source: raw['source']?.toString() == 'whoop' ? 'whoop' : 'manual',
    );
  }
}

class KaiFitnessGoal {
  const KaiFitnessGoal(
      {required this.metric, this.target, this.targetDate = ''});
  final KaiBodyMetric metric;
  final double? target;
  final String targetDate;

  Map<String, Object?> toJson() => {
        'metric': metric.name,
        'target': target,
        'targetDate': targetDate,
      };

  static KaiFitnessGoal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['metric']?.toString();
    final metric = KaiBodyMetric.values.where((item) => item.name == name);
    if (metric.isEmpty) return null;
    return KaiFitnessGoal(
      metric: metric.first,
      target: (raw['target'] as num?)?.toDouble(),
      targetDate: raw['targetDate']?.toString() ?? '',
    );
  }
}

class KaiFitnessSnapshot {
  const KaiFitnessSnapshot({
    this.steps = 0,
    this.waterGlasses = 0,
    this.sleepHours = 0,
    this.workoutDone = false,
    this.measurements = const [],
    this.goals = const [],
    this.whoop,
  });

  final int steps;
  final int waterGlasses;
  final double sleepHours;
  final bool workoutDone;
  final List<KaiBodyMeasurement> measurements;
  final List<KaiFitnessGoal> goals;
  final KaiWhoopHealthSnapshot? whoop;

  KaiBodyMeasurement? get latest => measurements.isEmpty
      ? null
      : (List<KaiBodyMeasurement>.of(measurements)
            ..sort((a, b) => a.date.compareTo(b.date)))
          .last;
  KaiFitnessGoal? goalFor(KaiBodyMetric metric) {
    for (final goal in goals) {
      if (goal.metric == metric) return goal;
    }
    return null;
  }

  KaiFitnessSnapshot copyWith({
    int? steps,
    int? waterGlasses,
    double? sleepHours,
    bool? workoutDone,
    List<KaiBodyMeasurement>? measurements,
    List<KaiFitnessGoal>? goals,
    KaiWhoopHealthSnapshot? whoop,
    bool clearWhoop = false,
  }) =>
      KaiFitnessSnapshot(
        steps: steps ?? this.steps,
        waterGlasses: waterGlasses ?? this.waterGlasses,
        sleepHours: sleepHours ?? this.sleepHours,
        workoutDone: workoutDone ?? this.workoutDone,
        measurements: measurements ?? this.measurements,
        goals: goals ?? this.goals,
        whoop: clearWhoop ? null : whoop ?? this.whoop,
      );

  Map<String, Object> toJson() => {
        'version': 3,
        'steps': steps,
        'waterGlasses': waterGlasses,
        'sleepHours': sleepHours,
        'workoutDone': workoutDone,
        'measurements': measurements.map((item) => item.toJson()).toList(),
        'goals': goals.map((item) => item.toJson()).toList(),
        if (whoop != null) 'whoop': whoop!.toJson(),
      };

  static KaiFitnessSnapshot? fromJson(Object? raw) {
    if (raw is! Map ||
        (raw['version'] != 1 && raw['version'] != 2 && raw['version'] != 3)) {
      return null;
    }
    final measurements = raw['measurements'] is List
        ? (raw['measurements'] as List)
            .map(KaiBodyMeasurement.fromJson)
            .whereType<KaiBodyMeasurement>()
            .toList()
        : <KaiBodyMeasurement>[];
    final goals = raw['goals'] is List
        ? (raw['goals'] as List)
            .map(KaiFitnessGoal.fromJson)
            .whereType<KaiFitnessGoal>()
            .toList()
        : <KaiFitnessGoal>[];
    return KaiFitnessSnapshot(
      steps: (raw['steps'] as num?)?.toInt() ?? 0,
      waterGlasses: (raw['waterGlasses'] as num?)?.toInt() ?? 0,
      sleepHours: (raw['sleepHours'] as num?)?.toDouble() ?? 0,
      workoutDone: raw['workoutDone'] == true,
      measurements: measurements,
      goals: goals,
      whoop: KaiWhoopHealthSnapshot.fromJson(raw['whoop']),
    );
  }
}

class KaiFitnessStore {
  KaiFitnessStore._();
  static final instance = KaiFitnessStore._();
  static const key = 'kai_fitness_snapshot_v1';

  Future<KaiFitnessSnapshot> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return const KaiFitnessSnapshot();
    try {
      return KaiFitnessSnapshot.fromJson(jsonDecode(raw)) ??
          const KaiFitnessSnapshot();
    } catch (_) {
      return const KaiFitnessSnapshot();
    }
  }

  Future<void> save(KaiFitnessSnapshot value) async =>
      (await SharedPreferences.getInstance())
          .setString(key, jsonEncode(value.toJson()));
}

class KaiFitnessTrackerCard extends StatefulWidget {
  const KaiFitnessTrackerCard({super.key});
  @override
  State<KaiFitnessTrackerCard> createState() => _KaiFitnessTrackerCardState();
}

class _KaiFitnessTrackerCardState extends State<KaiFitnessTrackerCard> {
  KaiFitnessSnapshot _value = const KaiFitnessSnapshot();
  KaiBodyMetric _metric = KaiBodyMetric.weight;

  @override
  void initState() {
    super.initState();
    KaiFitnessStore.instance.load().then((value) {
      if (mounted) setState(() => _value = value);
    });
  }

  Future<void> _edit() async {
    final updated = await showDialog<KaiFitnessSnapshot>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.78),
      builder: (_) => _KaiFitnessDialog(initial: _value),
    );
    if (updated != null && mounted) setState(() => _value = updated);
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('fitness-tracker-card'),
        decoration: BoxDecoration(
          color: _panel.withOpacity(0.91),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cyan.withOpacity(0.38)),
          boxShadow: [
            BoxShadow(color: _cyan.withOpacity(0.06), blurRadius: 20)
          ],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 7),
            child: Row(children: [
              const Icon(Icons.monitor_heart_outlined, color: _cyan, size: 18),
              const SizedBox(width: 9),
              const Expanded(
                  child: Text('PROJECT LIONHEART',
                      style: TextStyle(
                          color: Color(0xFFDCEAF4),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontFamily: 'monospace'))),
              TextButton(
                key: const Key('fitness-edit'),
                onPressed: _edit,
                child: const Text('EDIT',
                    style: TextStyle(
                        color: _cyan,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                _summary(),
                const SizedBox(height: 9),
                if (_value.whoop != null) ...[
                  _whoopSummary(),
                  const SizedBox(height: 9),
                ],
                _metricTabs(),
                const SizedBox(height: 7),
                SizedBox(
                  height: 110,
                  child: CustomPaint(
                    key: const Key('fitness-history-chart'),
                    painter: _FitnessChartPainter(
                      values: _value.measurements
                          .map((item) => item.valueOf(_metric))
                          .whereType<double>()
                          .toList(),
                      target: _value.goalFor(_metric)?.target,
                      color: _metric.color,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                _goalLine(),
                const SizedBox(height: 7),
                Text(
                    _value.whoop == null
                        ? 'LOCAL ONLY  -  WHOOP not connected'
                        : 'WHOOP  -  synced ${_shortSync(_value.whoop!.syncedAt)}  -  waist, lean mass + goals stay manual',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF6F8798),
                        fontSize: 8,
                        letterSpacing: 0.5,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
        ]),
      );

  String _shortSync(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _whoopSummary() {
    final whoop = _value.whoop!;
    String metric(double? value, {int decimals = 0}) =>
        value == null ? '--' : value.toStringAsFixed(decimals);
    final values = <(String, String)>[
      ('RECOVERY', '${metric(whoop.recoveryScore)}%'),
      ('HRV', '${metric(whoop.hrvMs)} ms'),
      ('STRAIN', metric(whoop.dayStrain, decimals: 1)),
      ('SLEEP', '${metric(whoop.sleepPerformance)}%'),
    ];
    return Container(
      key: const Key('fitness-whoop-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      decoration: BoxDecoration(
          color: _green.withOpacity(.055),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _green.withOpacity(.2))),
      child: Row(
          children: values
              .map((item) => Expanded(
                      child: Column(children: [
                    Text(item.$2,
                        style: const TextStyle(
                            color: _green,
                            fontSize: 10,
                            fontWeight: FontWeight.w900)),
                    Text(item.$1,
                        style: const TextStyle(
                            color: Color(0xFF71899A),
                            fontSize: 6.5,
                            letterSpacing: .5,
                            fontFamily: 'monospace')),
                  ])))
              .toList()),
    );
  }

  Widget _summary() {
    String value(KaiBodyMetric metric) {
      final number = _value.latest?.valueOf(metric);
      return number == null
          ? '--'
          : number.toStringAsFixed(metric == KaiBodyMetric.rhr ? 0 : 1);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
      decoration: BoxDecoration(
          color: const Color(0xFF0B1A26).withOpacity(0.88),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _cyan.withOpacity(0.16))),
      child: Row(
          children: KaiBodyMetric.values
              .map((metric) => Expanded(
                      child: Column(children: [
                    Text(value(metric),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: metric.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w900)),
                    Text(
                        metric == KaiBodyMetric.leanMass
                            ? 'LEAN KG'
                            : '${metric.label.toUpperCase()} ${metric.unit.toUpperCase()}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFF71899A),
                            fontSize: 6.5,
                            letterSpacing: 0.35,
                            fontFamily: 'monospace')),
                  ])))
              .toList()),
    );
  }

  Widget _metricTabs() => Row(
          children: KaiBodyMetric.values.map((metric) {
        final selected = metric == _metric;
        return Expanded(
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            key: Key('fitness-metric-${metric.name}'),
            onTap: () => setState(() => _metric = metric),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                  color: selected
                      ? metric.color.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: selected
                          ? metric.color.withOpacity(0.45)
                          : Colors.white.withOpacity(0.06))),
              child: Text(metric.label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected ? metric.color : const Color(0xFF71899A),
                      fontSize: 8,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ));
      }).toList());

  Widget _goalLine() {
    final goal = _value.goalFor(_metric);
    final text = goal?.target == null
        ? 'No ${_metric.label.toLowerCase()} goal set'
        : 'Goal ${goal!.target!.toStringAsFixed(_metric == KaiBodyMetric.rhr ? 0 : 1)} ${_metric.unit}${goal.targetDate.isEmpty ? '' : ' by ${goal.targetDate}'}';
    return Row(children: [
      Icon(Icons.flag_outlined, size: 14, color: _metric.color),
      const SizedBox(width: 7),
      Expanded(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF9FB6C8), fontSize: 9.5))),
      Text('${_value.measurements.length} entries',
          style: const TextStyle(color: Color(0xFF60798A), fontSize: 8)),
    ]);
  }
}

class _KaiFitnessDialog extends StatefulWidget {
  const _KaiFitnessDialog({required this.initial});
  final KaiFitnessSnapshot initial;
  @override
  State<_KaiFitnessDialog> createState() => _KaiFitnessDialogState();
}

class _KaiFitnessDialogState extends State<_KaiFitnessDialog> {
  late KaiFitnessSnapshot _value = widget.initial;
  late String _date = DateTime.now().toIso8601String().substring(0, 10);
  final Map<KaiBodyMetric, TextEditingController> _measure = {};
  final Map<KaiBodyMetric, TextEditingController> _target = {};
  final Map<KaiBodyMetric, TextEditingController> _targetDate = {};
  final TextEditingController _whoopClientId = TextEditingController();
  final TextEditingController _whoopClientSecret = TextEditingController();
  KaiWhoopConnectionStatus _whoopStatus =
      const KaiWhoopConnectionStatus(configured: false, connected: false);
  bool _whoopBusy = false;
  String? _whoopMessage;

  @override
  void initState() {
    super.initState();
    for (final metric in KaiBodyMetric.values) {
      _measure[metric] = TextEditingController();
      final goal = _value.goalFor(metric);
      _target[metric] =
          TextEditingController(text: goal?.target?.toString() ?? '');
      _targetDate[metric] = TextEditingController(text: goal?.targetDate ?? '');
    }
    KaiWhoopService.instance.status().then((status) {
      if (mounted) setState(() => _whoopStatus = status);
    });
  }

  @override
  void dispose() {
    for (final controller in [
      ..._measure.values,
      ..._target.values,
      ..._targetDate.values
    ]) {
      controller.dispose();
    }
    _whoopClientId.dispose();
    _whoopClientSecret.dispose();
    super.dispose();
  }

  Future<void> _connectWhoop() async {
    setState(() {
      _whoopBusy = true;
      _whoopMessage = 'Waiting for WHOOP approval in your browser...';
    });
    try {
      await KaiWhoopService.instance.connect(
        clientId: _whoopClientId.text,
        clientSecret: _whoopClientSecret.text,
      );
      _whoopClientSecret.clear();
      _whoopStatus = await KaiWhoopService.instance.status();
      await _syncWhoop();
    } catch (error) {
      if (mounted) setState(() => _whoopMessage = error.toString());
    } finally {
      if (mounted) setState(() => _whoopBusy = false);
    }
  }

  Future<void> _syncWhoop() async {
    setState(() {
      _whoopBusy = true;
      _whoopMessage = 'Refreshing WHOOP...';
    });
    try {
      final whoop = await KaiWhoopService.instance.sync();
      final date = whoop.syncedAt.toLocal().toIso8601String().substring(0, 10);
      final existing = _value.measurements.where((item) => item.date == date);
      final old = existing.isEmpty ? null : existing.first;
      final imported = KaiBodyMeasurement(
        date: date,
        weight: whoop.weightKg ?? old?.weight,
        waist: old?.waist,
        rhr: whoop.restingHeartRate ?? old?.rhr,
        leanMass: old?.leanMass,
        source: 'whoop',
      );
      final history = [
        ..._value.measurements.where((item) => item.date != date),
        imported,
      ]..sort((a, b) => a.date.compareTo(b.date));
      _update(_value.copyWith(
        sleepHours: whoop.sleepHours ?? _value.sleepHours,
        workoutDone: whoop.workoutToday || _value.workoutDone,
        measurements: history,
        whoop: whoop,
      ));
      if (mounted) {
        setState(() {
          _whoopStatus =
              const KaiWhoopConnectionStatus(configured: true, connected: true);
          _whoopMessage =
              'WHOOP is synced. Weight, RHR, Recovery, HRV, Strain and sleep are current.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _whoopMessage = error.toString());
    } finally {
      if (mounted) setState(() => _whoopBusy = false);
    }
  }

  Future<void> _disconnectWhoop() async {
    setState(() {
      _whoopBusy = true;
      _whoopMessage = 'Revoking WHOOP access...';
    });
    try {
      await KaiWhoopService.instance.disconnect();
      _update(_value.copyWith(clearWhoop: true));
      if (mounted) {
        setState(() {
          _whoopStatus = const KaiWhoopConnectionStatus(
              configured: true, connected: false);
          _whoopMessage =
              'WHOOP access revoked. Imported history was preserved.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _whoopMessage = error.toString());
    } finally {
      if (mounted) setState(() => _whoopBusy = false);
    }
  }

  void _saveGoals() {
    final goals = KaiBodyMetric.values
        .map((metric) => KaiFitnessGoal(
              metric: metric,
              target: double.tryParse(_target[metric]!.text.trim()),
              targetDate: _targetDate[metric]!.text.trim(),
            ))
        .toList();
    _update(_value.copyWith(goals: goals));
  }

  void _addMeasurement() {
    final item = KaiBodyMeasurement(
      date: _date,
      weight: double.tryParse(_measure[KaiBodyMetric.weight]!.text),
      waist: double.tryParse(_measure[KaiBodyMetric.waist]!.text),
      rhr: double.tryParse(_measure[KaiBodyMetric.rhr]!.text),
      leanMass: double.tryParse(_measure[KaiBodyMetric.leanMass]!.text),
    );
    if (KaiBodyMetric.values.every((metric) => item.valueOf(metric) == null)) {
      return;
    }
    final history = [
      ..._value.measurements.where((entry) => entry.date != _date),
      item
    ]..sort((a, b) => a.date.compareTo(b.date));
    for (final controller in _measure.values) {
      controller.clear();
    }
    _update(_value.copyWith(measurements: history));
  }

  void _update(KaiFitnessSnapshot next) {
    setState(() => _value = next);
    unawaited(KaiFitnessStore.instance.save(next));
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 860),
          child: Container(
            decoration: BoxDecoration(
                color: const Color(0xFF07111C),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _cyan.withOpacity(0.45))),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
                child: Row(children: [
                  const Icon(Icons.monitor_heart_outlined, color: _cyan),
                  const SizedBox(width: 10),
                  const Expanded(
                      child: Text('Project Lionheart',
                          style: TextStyle(
                              color: Color(0xFFDCEAF4),
                              fontSize: 17,
                              fontWeight: FontWeight.w800))),
                  TextButton(
                      key: const Key('fitness-dialog-done'),
                      onPressed: () => Navigator.pop(context, _value),
                      child:
                          const Text('DONE', style: TextStyle(color: _cyan))),
                ]),
              ),
              Expanded(
                  child: ListView(
                      key: const Key('fitness-edit-scroll'),
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      children: [
                    _section('WHOOP CONNECTION', [
                      const Text(
                          'Read-only import: weight, RHR, Recovery, HRV, Strain, sleep and workouts. Homecoming never asks for your WHOOP password. Waist, lean mass, water and Project Lionheart goals stay manual.',
                          style: TextStyle(
                              color: Color(0xFF9FB6C8), fontSize: 11)),
                      const SizedBox(height: 8),
                      const SelectableText('Redirect URL: $kaiWhoopRedirectUri',
                          key: Key('fitness-whoop-redirect'),
                          style: TextStyle(
                              color: _cyan,
                              fontSize: 10,
                              fontFamily: 'monospace')),
                      const SizedBox(height: 8),
                      if (!_whoopStatus.configured) ...[
                        TextField(
                            key: const Key('fitness-whoop-client-id'),
                            controller: _whoopClientId,
                            decoration: _decoration('WHOOP Client ID')),
                        const SizedBox(height: 8),
                        TextField(
                            key: const Key('fitness-whoop-client-secret'),
                            controller: _whoopClientSecret,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: _decoration('WHOOP Client Secret')),
                        const SizedBox(height: 8),
                      ],
                      if (_whoopMessage != null) ...[
                        Text(_whoopMessage!,
                            key: const Key('fitness-whoop-message'),
                            style: TextStyle(
                                color: _whoopMessage!.contains('synced')
                                    ? _green
                                    : const Color(0xFFFFB84D),
                                fontSize: 10)),
                        const SizedBox(height: 8),
                      ],
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (!_whoopStatus.connected)
                          FilledButton.icon(
                              key: const Key('fitness-whoop-connect'),
                              onPressed: _whoopBusy ? null : _connectWhoop,
                              icon: const Icon(Icons.link),
                              label: const Text('Connect WHOOP')),
                        if (_whoopStatus.connected) ...[
                          FilledButton.icon(
                              key: const Key('fitness-whoop-sync'),
                              onPressed: _whoopBusy ? null : _syncWhoop,
                              icon: const Icon(Icons.sync),
                              label: const Text('Refresh now')),
                          OutlinedButton.icon(
                              key: const Key('fitness-whoop-disconnect'),
                              onPressed: _whoopBusy ? null : _disconnectWhoop,
                              icon: const Icon(Icons.link_off),
                              label: const Text('Disconnect + revoke')),
                        ],
                        if (_whoopBusy)
                          const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                      ]),
                    ]),
                    const SizedBox(height: 14),
                    _section('ADD BODY MEASUREMENT', [
                      TextFormField(
                          initialValue: _date,
                          decoration: _decoration('Date (YYYY-MM-DD)'),
                          onChanged: (value) => _date = value.trim()),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: KaiBodyMetric.values
                              .map((metric) => SizedBox(
                                  width: 220,
                                  child: TextField(
                                      key: Key('fitness-input-${metric.name}'),
                                      controller: _measure[metric],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: _decoration(
                                          '${metric.label} (${metric.unit})'))))
                              .toList()),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                          key: const Key('fitness-add-measurement'),
                          onPressed: _addMeasurement,
                          icon: const Icon(Icons.add_chart),
                          label: const Text('Add or replace this date')),
                    ]),
                    const SizedBox(height: 14),
                    _section('TARGET GOALS + DATES', [
                      for (final metric in KaiBodyMetric.values)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                              SizedBox(
                                  width: 100,
                                  child: Text(metric.label,
                                      style: TextStyle(
                                          color: metric.color,
                                          fontWeight: FontWeight.w700))),
                              Expanded(
                                  child: TextField(
                                      key: Key('fitness-goal-${metric.name}'),
                                      controller: _target[metric],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: _decoration(
                                          'Target ${metric.unit}'))),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: TextField(
                                      key: Key('fitness-date-${metric.name}'),
                                      controller: _targetDate[metric],
                                      decoration: _decoration('YYYY-MM-DD'))),
                            ])),
                      FilledButton.icon(
                          key: const Key('fitness-save-goals'),
                          onPressed: _saveGoals,
                          icon: const Icon(Icons.flag_outlined),
                          label: const Text('Save goals')),
                    ]),
                    const SizedBox(height: 14),
                    _section('DAILY HABITS', [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _habit('Steps', _value.steps.toDouble(), 500,
                            (v) => _update(_value.copyWith(steps: v.round()))),
                        _habit(
                            'Water glasses',
                            _value.waterGlasses.toDouble(),
                            1,
                            (v) => _update(
                                _value.copyWith(waterGlasses: v.round()))),
                        _habit('Sleep hours', _value.sleepHours, .5,
                            (v) => _update(_value.copyWith(sleepHours: v))),
                        FilterChip(
                            label: Text(_value.workoutDone
                                ? 'Workout done'
                                : 'Workout not logged'),
                            selected: _value.workoutDone,
                            onSelected: (v) =>
                                _update(_value.copyWith(workoutDone: v))),
                      ]),
                    ]),
                    const SizedBox(height: 14),
                    _section('MEASUREMENT HISTORY', [
                      if (_value.measurements.isEmpty)
                        const Text('No measurements recorded yet.',
                            style: TextStyle(color: Color(0xFF71899A)))
                      else
                        for (final item in _value.measurements.reversed)
                          ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(item.date,
                                  style: const TextStyle(
                                      color: Color(0xFFDCEAF4))),
                              subtitle: Text(
                                  KaiBodyMetric.values
                                      .map((metric) {
                                        final v = item.valueOf(metric);
                                        return v == null
                                            ? null
                                            : '${metric.label} ${v.toStringAsFixed(metric == KaiBodyMetric.rhr ? 0 : 1)} ${metric.unit}';
                                      })
                                      .whereType<String>()
                                      .join('  -  '),
                                  style: const TextStyle(
                                      color: Color(0xFF8FA7B8))),
                              leading: item.source == 'whoop'
                                  ? const Icon(Icons.monitor_heart_outlined,
                                      color: _green, size: 16)
                                  : null,
                              trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Color(0xFFFF6B78)),
                                  onPressed: () => _update(_value.copyWith(
                                      measurements: _value.measurements
                                          .where((entry) => entry != item)
                                          .toList())))),
                    ]),
                    const SizedBox(height: 10),
                    const Text(
                        'Stored locally on this desktop. This is a personal log, not medical advice or a connected health record.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Color(0xFF6F8798), fontSize: 9)),
                  ])),
            ]),
          ),
        ),
      );

  InputDecoration _decoration(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF71899A)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.025),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)));
  Widget _section(String title, List<Widget> children) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.018),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.07))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title,
            style: const TextStyle(
                color: _cyan,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
                fontFamily: 'monospace')),
        const SizedBox(height: 10),
        ...children
      ]));
  Widget _habit(String label, double value, double step,
          ValueChanged<double> changed) =>
      Container(
          width: 210,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withOpacity(.08))),
          child: Row(children: [
            Expanded(
                child: Text(
                    '$label: ${value.toStringAsFixed(step < 1 ? 1 : 0)}',
                    style: const TextStyle(color: Color(0xFFB8CBD8)))),
            IconButton(
                onPressed: () => changed(math.max(0, value - step)),
                icon: const Icon(Icons.remove, size: 16)),
            IconButton(
                onPressed: () => changed(value + step),
                icon: const Icon(Icons.add, size: 16))
          ]));
}

class _FitnessChartPainter extends CustomPainter {
  const _FitnessChartPainter(
      {required this.values, required this.target, required this.color});
  final List<double> values;
  final double? target;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withOpacity(.07)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) {
      final text = TextPainter(
          text: const TextSpan(
              text: 'Add measurements to build the graph',
              style: TextStyle(color: Color(0xFF60798A), fontSize: 10)),
          textDirection: TextDirection.ltr)
        ..layout();
      text.paint(
          canvas,
          Offset(
              (size.width - text.width) / 2, (size.height - text.height) / 2));
      return;
    }
    final all = [...values, if (target != null) target!];
    var minValue = all.reduce(math.min);
    var maxValue = all.reduce(math.max);
    if (minValue == maxValue) {
      minValue -= 1;
      maxValue += 1;
    }
    double y(double value) =>
        size.height -
        ((value - minValue) / (maxValue - minValue) * (size.height - 12)) -
        6;
    if (target != null) {
      final paint = Paint()
        ..color = _amber.withOpacity(.65)
        ..strokeWidth = 1;
      canvas.drawLine(
          Offset(0, y(target!)), Offset(size.width, y(target!)), paint);
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
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _FitnessChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.target != target ||
      oldDelegate.color != color;
}
