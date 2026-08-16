// KaiProjectPortfolio — live project sovereignty HUD.
//
// The desktop rail remains backed by KaiProjectService. This renderer maps
// every project to one angular sector and every governed layer to one exact
// annular hit target. Selecting a layer reveals its evidence below the wheel;
// labels never participate in hit testing or paint over another section.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/core/kai_factory_daily_lane.dart';
import '../services/core/kai_project_service.dart';
import '../services/core/kai_delivery_box.dart';

const _hudCyan = Color(0xFF53E8FF);
const _hudInk = Color(0xFFD9FAFF);
const _hudMuted = Color(0xFF79A8B0);
const _hudGrid = Color(0xFF123B43);
const _hudPanel = Color(0xFF061A20);
const _hudBackground = Color(0xFF031014);
const _hudAmber = Color(0xFFFFBD4A);
const _hudGreen = Color(0xFF5AF2A0);
const _hudRed = Color(0xFFFF6475);
const _hudViolet = Color(0xFFBF8CFF);

@visibleForTesting
class KaiDeliveryPhaseSummary {
  final int total;
  final int verified;
  final int active;
  final int awaitingSponsor;
  final int blocked;
  final String kaiNext;
  final String sponsorNext;

  const KaiDeliveryPhaseSummary({
    required this.total,
    required this.verified,
    required this.active,
    required this.awaitingSponsor,
    required this.blocked,
    required this.kaiNext,
    required this.sponsorNext,
  });
}

@visibleForTesting
KaiDeliveryPhaseSummary summarizeDeliveryBoxes(List<KaiDeliveryBox> boxes) {
  int count(KaiDeliveryBoxState state) =>
      boxes.where((box) => box.state == state).length;
  final nextAgent = boxes.where((box) =>
      box.owner == KaiDeliveryBoxOwner.agent &&
      {
        KaiDeliveryBoxState.ready,
        KaiDeliveryBoxState.active,
        KaiDeliveryBoxState.repairing,
        KaiDeliveryBoxState.evidenceReview,
      }.contains(box.state));
  final sponsor =
      boxes.where((box) => box.state == KaiDeliveryBoxState.awaitingSponsor);
  return KaiDeliveryPhaseSummary(
    total: boxes.length,
    verified: count(KaiDeliveryBoxState.verified),
    active: count(KaiDeliveryBoxState.active) +
        count(KaiDeliveryBoxState.repairing) +
        count(KaiDeliveryBoxState.evidenceReview),
    awaitingSponsor: count(KaiDeliveryBoxState.awaitingSponsor),
    blocked: count(KaiDeliveryBoxState.blocked),
    kaiNext: nextAgent.isEmpty
        ? 'No eligible local agent box in this phase.'
        : nextAgent.first.outcome,
    sponsorNext: sponsor.isEmpty
        ? 'No sponsor decision is currently exposed.'
        : sponsor.map((box) => box.outcome).join(' • '),
  );
}

class KaiProjectPortfolio extends StatefulWidget {
  const KaiProjectPortfolio({
    super.key,
    required this.personaId,
    this.workspaceRoot,
    this.onOpenProject,
  });

  final String personaId;

  /// Read-only. Used by the service to sort the local project first.
  final String? workspaceRoot;

  final void Function(KaiProject project)? onOpenProject;

  @override
  State<KaiProjectPortfolio> createState() => _KaiProjectPortfolioState();
}

class _KaiProjectPortfolioState extends State<KaiProjectPortfolio> {
  String? _selectedProjectId;
  int? _selectedLayerIndex;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<KaiProject>>(
      stream: KaiProjectService.instance.watchPortfolio(
        widget.personaId,
        workspaceRoot: widget.workspaceRoot,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _PortfolioNotice(
            'Portfolio unavailable — tracker evidence could not be read.',
          );
        }
        if (!snapshot.hasData) {
          return const _PortfolioNotice('Locking project signals…');
        }
        final projects = snapshot.data!;
        if (projects.isEmpty) {
          return const _PortfolioNotice('No governed projects are registered.');
        }

        final selection = _resolveSelection(projects);
        final stageCount = projects.fold<int>(
          0,
          (total, project) => total + project.layers.length,
        );

        return Container(
          decoration: BoxDecoration(
            color: _hudBackground.withValues(alpha: 0.94),
            border: Border.all(color: _hudGrid),
          ),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HudHeader(),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final side = math.min(constraints.maxWidth, 360.0);
                  return Align(
                    child: SizedBox.square(
                      dimension: side,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          final hit = projectSectorHitTest(
                            size: Size.square(side),
                            position: details.localPosition,
                            phaseCounts: [
                              for (final project in projects)
                                project.layers.length,
                            ],
                          );
                          if (hit == null) return;
                          setState(() {
                            _selectedProjectId = projects[hit.projectIndex].id;
                            _selectedLayerIndex = hit.phaseIndex;
                          });
                        },
                        child: CustomPaint(
                          painter: _ProjectSectorPainter(
                            projects: projects,
                            selected: selection == null
                                ? null
                                : ProjectSectorHit(
                                    selection.projectIndex,
                                    selection.layerIndex,
                                  ),
                          ),
                          child: Semantics(label: _semanticSummary(projects)),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              const _StatusLegend(),
              const SizedBox(height: 8),
              _HudReadouts(
                projectCount: projects.length,
                stageCount: stageCount,
                selection: selection,
              ),
              if (selection != null) ...[
                const SizedBox(height: 8),
                _StageDrawer(
                  project: selection.project,
                  layer: selection.layer,
                  onOpenProject: widget.onOpenProject == null
                      ? null
                      : () => widget.onOpenProject!(selection.project),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  _ResolvedSelection? _resolveSelection(List<KaiProject> projects) {
    if (_selectedProjectId == null || _selectedLayerIndex == null) return null;
    final projectIndex = projects.indexWhere(
      (project) => project.id == _selectedProjectId,
    );
    if (projectIndex < 0) return null;
    final project = projects[projectIndex];
    final layerIndex = _selectedLayerIndex!;
    if (layerIndex < 0 || layerIndex >= project.layers.length) return null;
    return _ResolvedSelection(
      projectIndex: projectIndex,
      layerIndex: layerIndex,
      project: project,
      layer: project.layers[layerIndex],
    );
  }

  static String _semanticSummary(List<KaiProject> projects) {
    final parts = projects.map((project) {
      return '${project.name}: ${project.acceptedPhases} of '
          '${project.layers.length} stages accepted';
    });
    return 'Project sovereignty wheel. ${parts.join('. ')}.';
  }
}

class _HudHeader extends StatelessWidget {
  const _HudHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OVERLORD KAI // OPS',
                style: TextStyle(
                  color: _hudCyan,
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
              SizedBox(height: 3),
              Text(
                'PROJECT SOVEREIGNTY MATRIX',
                style: TextStyle(
                  color: _hudInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'STATUS DATE 08.08.2026',
                style: TextStyle(
                  color: _hudMuted,
                  fontSize: 7,
                  letterSpacing: 0.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        Text(
          '● ONLINE',
          style: TextStyle(
            color: _hudGreen,
            fontSize: 9,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        _LegendItem(color: _hudGreen, label: 'Accepted'),
        _LegendItem(color: _hudAmber, label: 'Active gate'),
        _LegendItem(color: _hudViolet, label: 'Proven work'),
        _LegendItem(color: _hudGrid, label: 'Future stage'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            border: Border.all(color: color),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: _hudMuted, fontSize: 9)),
      ],
    );
  }
}

class _HudReadouts extends StatelessWidget {
  const _HudReadouts({
    required this.projectCount,
    required this.stageCount,
    required this.selection,
  });

  final int projectCount;
  final int stageCount;
  final _ResolvedSelection? selection;

  @override
  Widget build(BuildContext context) {
    final selected = selection;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _Readout(label: 'SECTORS', value: '$projectCount CLAIMED'),
        _Readout(label: 'STAGES', value: '$stageCount GOVERNED'),
        _Readout(
          label: 'SELECTED',
          value: selected == null
              ? 'AWAITING INPUT'
              : '${selected.project.name} / P${selected.layer.n}',
          danger: selected?.project.blockers.isNotEmpty ?? false,
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 5, 8, 6),
      decoration: const BoxDecoration(
        color: Color(0xB3061A20),
        border: Border(left: BorderSide(color: _hudGrid, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _hudMuted,
              fontSize: 8,
              letterSpacing: 1,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: danger ? _hudRed : _hudInk,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _StageDrawer extends StatelessWidget {
  const _StageDrawer({
    required this.project,
    required this.layer,
    this.onOpenProject,
  });

  final KaiProject project;
  final KaiLayer layer;
  final VoidCallback? onOpenProject;

  @override
  Widget build(BuildContext context) {
    final gate = layer.checklist.isEmpty
        ? 'No accepted exit gate is registered.'
        : layer.checklist.first;
    final latest = layer.evidence.isEmpty
        ? 'No evidence recorded for this stage.'
        : layer.evidence.last;
    final blocker = project.blockers.isEmpty
        ? 'No blocking condition recorded.'
        : project.blockers.first;
    final boxes = layer.deliveryBoxes;
    final boxSummary = summarizeDeliveryBoxes(boxes);

    return Container(
      key: const ValueKey('project-sector-drawer'),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: _hudPanel,
        border: Border.all(color: _hudGrid),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${project.name.toUpperCase()} / ${project.proofState.label.toUpperCase()}',
                  style: const TextStyle(
                    color: _hudCyan,
                    fontSize: 9,
                    letterSpacing: 0.8,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (onOpenProject != null)
                TextButton(
                  onPressed: onOpenProject,
                  style: TextButton.styleFrom(
                    foregroundColor: _hudCyan,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 8),
                  ),
                  child: const Text('OPEN MAP'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'P${layer.n} · ${layer.title}',
            style: const TextStyle(
              color: _hudInk,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (project.latestAdvance.isNotEmpty) ...[
            _DrawerLine(
              label: 'CURRENT',
              value: project.latestAdvance,
              color: _hudViolet,
            ),
            const SizedBox(height: 5),
          ],
          if (project.id == KaiProjectService.factoryId) ...[
            const KaiFactoryDailyLanePanel(
              lane: boothSignalFactoryDailyLane,
            ),
            const SizedBox(height: 7),
          ],
          _DrawerLine(label: 'EXIT GATE', value: gate, color: _hudAmber),
          const SizedBox(height: 5),
          _DrawerLine(label: 'BLOCKER', value: blocker, color: _hudRed),
          const SizedBox(height: 5),
          _DrawerLine(label: 'LATEST', value: latest, color: _hudMuted),
          const SizedBox(height: 7),
          Text(
            'BOXES ${boxSummary.total}  •  VERIFIED ${boxSummary.verified}  •  '
            'ACTIVE ${boxSummary.active}  •  AWAITING SPONSOR ${boxSummary.awaitingSponsor}  •  '
            'BLOCKED ${boxSummary.blocked}',
            key: const ValueKey('phase-box-counts'),
            style: const TextStyle(
              color: _hudCyan,
              fontSize: 8,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          _DrawerLine(
            label: 'KAI IS DOING NEXT',
            value: boxSummary.kaiNext,
            color: _hudGreen,
          ),
          const SizedBox(height: 5),
          _DrawerLine(
            label: 'ONLY YOU CAN DECIDE',
            value: boxSummary.sponsorNext,
            color: _hudAmber,
          ),
          if (boxes.isNotEmpty) ...[
            const SizedBox(height: 7),
            for (final box in boxes) _DeliveryBoxLine(box),
          ],
        ],
      ),
    );
  }
}

@visibleForTesting
class KaiFactoryDailyLanePanel extends StatelessWidget {
  const KaiFactoryDailyLanePanel({
    super.key,
    required this.lane,
  });

  final KaiFactoryDailyLane lane;

  Color _stateColor(KaiFactoryDailyStation station) => switch (station.state) {
        KaiFactoryDailyStationState.tested => _hudViolet,
        KaiFactoryDailyStationState.sponsorCompleted => _hudAmber,
        KaiFactoryDailyStationState.verifiedLive => _hudGreen,
        KaiFactoryDailyStationState.active => _hudGreen,
        KaiFactoryDailyStationState.future => _hudMuted,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('factory-daily-lane'),
      width: double.infinity,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: _hudBackground,
        border: Border.all(color: _hudViolet.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FACTORY DAILY / ${lane.productName.toUpperCase()}',
            style: const TextStyle(
              color: _hudViolet,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 5),
          for (final station in lane.stations)
            Container(
              key: ValueKey('factory-daily-station-${station.id}'),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
              decoration: BoxDecoration(
                color: _hudPanel,
                border: Border(
                  left: BorderSide(color: _stateColor(station), width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${station.label.toUpperCase()}  •  ${station.state.label}'
                    '${station.isNextGate ? '  •  NEXT GATE' : ''}',
                    style: TextStyle(
                      color: _stateColor(station),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${station.proof.label} — ${station.detail}',
                    style: const TextStyle(
                      color: _hudInk,
                      fontSize: 8,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'REVENUE  •  ${lane.revenueProof}',
            key: const ValueKey('factory-daily-revenue-proof'),
            style: const TextStyle(
              color: _hudRed,
              fontSize: 8,
              height: 1.25,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryBoxLine extends StatelessWidget {
  const _DeliveryBoxLine(this.box);

  final KaiDeliveryBox box;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          key: ValueKey('delivery-box-${box.identity}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 98,
              child: Text(
                box.state.wireName.toUpperCase(),
                style: const TextStyle(
                  color: _hudMuted,
                  fontSize: 7,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            Expanded(
              child: Text(
                box.outcome,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _hudInk, fontSize: 8),
              ),
            ),
          ],
        ),
      );
}

class _DrawerLine extends StatelessWidget {
  const _DrawerLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: TextStyle(
              color: color,
              fontSize: 8,
              letterSpacing: 0.7,
              fontFamily: 'monospace',
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: _hudInk, fontSize: 9, height: 1.25),
          ),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _PortfolioNotice extends StatelessWidget {
  const _PortfolioNotice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _hudPanel,
        border: Border.all(color: _hudGrid),
      ),
      child: Text(
        message,
        style: const TextStyle(color: _hudMuted, fontSize: 11),
      ),
    );
  }
}

class _ResolvedSelection {
  const _ResolvedSelection({
    required this.projectIndex,
    required this.layerIndex,
    required this.project,
    required this.layer,
  });

  final int projectIndex;
  final int layerIndex;
  final KaiProject project;
  final KaiLayer layer;
}

@visibleForTesting
class ProjectSectorHit {
  const ProjectSectorHit(this.projectIndex, this.phaseIndex);

  final int projectIndex;
  final int phaseIndex;

  @override
  bool operator ==(Object other) {
    return other is ProjectSectorHit &&
        other.projectIndex == projectIndex &&
        other.phaseIndex == phaseIndex;
  }

  @override
  int get hashCode => Object.hash(projectIndex, phaseIndex);

  @override
  String toString() => 'ProjectSectorHit($projectIndex, $phaseIndex)';
}

class _SectorGeometry {
  _SectorGeometry(this.size)
      : center = Offset(size.width / 2, size.height / 2),
        maxRadius = size.shortestSide / 2;

  final Size size;
  final Offset center;
  final double maxRadius;

  double get phaseInner => maxRadius * 0.27;
  double get phaseOuter => maxRadius * 0.77;
  double get dividerOuter => maxRadius * 0.79;
  double get outerRing => maxRadius * 0.83;
  double get projectLabelRadius => maxRadius * 0.91;
}

/// Maps a pointer to the exact annular project/layer section painted below.
/// Labels and glow effects are deliberately excluded from this geometry.
@visibleForTesting
ProjectSectorHit? projectSectorHitTest({
  required Size size,
  required Offset position,
  required List<int> phaseCounts,
}) {
  if (phaseCounts.isEmpty) return null;
  final geometry = _SectorGeometry(size);
  final delta = position - geometry.center;
  final radius = delta.distance;
  if (radius < geometry.phaseInner || radius > geometry.phaseOuter) {
    return null;
  }

  final sectorSweep = math.pi * 2 / phaseCounts.length;
  final firstStart = -math.pi / 2 - sectorSweep / 2;
  var relativeAngle = math.atan2(delta.dy, delta.dx) - firstStart;
  relativeAngle %= math.pi * 2;
  if (relativeAngle < 0) relativeAngle += math.pi * 2;
  final projectIndex = (relativeAngle / sectorSweep)
      .floor()
      .clamp(0, phaseCounts.length - 1)
      .toInt();

  final phaseCount = phaseCounts[projectIndex];
  if (phaseCount <= 0) return null;
  final band = (geometry.phaseOuter - geometry.phaseInner) / phaseCount;
  final phaseIndex = ((radius - geometry.phaseInner) / band)
      .floor()
      .clamp(0, phaseCount - 1)
      .toInt();
  return ProjectSectorHit(projectIndex, phaseIndex);
}

class _ProjectSectorPainter extends CustomPainter {
  const _ProjectSectorPainter({required this.projects, required this.selected});

  final List<KaiProject> projects;
  final ProjectSectorHit? selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (projects.isEmpty) return;
    final geometry = _SectorGeometry(size);
    final sectorSweep = math.pi * 2 / projects.length;
    final firstStart = -math.pi / 2 - sectorSweep / 2;

    _drawOuterRing(canvas, geometry);

    for (var projectIndex = 0; projectIndex < projects.length; projectIndex++) {
      final project = projects[projectIndex];
      final start = firstStart + projectIndex * sectorSweep;
      final end = start + sectorSweep;
      if (project.layers.isNotEmpty) {
        final band =
            (geometry.phaseOuter - geometry.phaseInner) / project.layers.length;
        for (var layerIndex = 0;
            layerIndex < project.layers.length;
            layerIndex++) {
          final layer = project.layers[layerIndex];
          final inner = geometry.phaseInner + layerIndex * band + 1.2;
          final outer = geometry.phaseInner + (layerIndex + 1) * band - 1.2;
          final isSelected =
              selected == ProjectSectorHit(projectIndex, layerIndex);
          _drawPhase(
            canvas,
            geometry.center,
            project,
            layer,
            inner,
            outer,
            start,
            end,
            isSelected,
          );
        }
      }
      _drawDivider(canvas, geometry, start);
      _drawArcText(
        canvas,
        text: project.name.toUpperCase(),
        center: geometry.center,
        radius: geometry.projectLabelRadius,
        startAngle: start + sectorSweep * 0.12,
        endAngle: end - sectorSweep * 0.12,
        color: _hudCyan,
        maximumFontSize: 11,
        letterSpacing: 0.9,
      );
    }

    _drawCore(
      canvas,
      geometry.center,
      geometry.phaseInner - 2,
      projects.length,
    );
  }

  void _drawPhase(
    Canvas canvas,
    Offset center,
    KaiProject project,
    KaiLayer layer,
    double inner,
    double outer,
    double start,
    double end,
    bool isSelected,
  ) {
    const angleGap = 0.012;
    final path = _annularPath(
      center,
      inner,
      outer,
      start + angleGap,
      end - angleGap,
    );
    final accepted = project.isPhaseAccepted(layer);
    final active = layer.n == project.activePhase;
    final evidenced = project.phaseHasEvidence(layer);
    final color = accepted
        ? _hudGreen
        : (active ? _hudAmber : (evidenced ? _hudViolet : _hudGrid));
    final fillAlpha = accepted ? 0.23 : ((active || evidenced) ? 0.22 : 0.28);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = (accepted || active || evidenced ? color : _hudPanel)
            .withValues(alpha: fillAlpha),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.0 : 0.9
        ..color = isSelected ? _hudCyan : color,
    );

    final midRadius = (inner + outer) / 2;
    final bandThickness = outer - inner;
    _drawArcText(
      canvas,
      text: layer.title,
      center: center,
      radius: midRadius,
      startAngle: start + 0.07,
      endAngle: end - 0.07,
      color: _hudInk,
      maximumFontSize: math.max(6.5, math.min(9.5, bandThickness * 0.72)),
      letterSpacing: 0,
    );
  }

  static Path _annularPath(
    Offset center,
    double inner,
    double outer,
    double start,
    double end,
  ) {
    final outerRect = Rect.fromCircle(center: center, radius: outer);
    final innerRect = Rect.fromCircle(center: center, radius: inner);
    final sweep = end - start;
    final outerStart =
        center + Offset(math.cos(start), math.sin(start)) * outer;
    final innerEnd = center + Offset(math.cos(end), math.sin(end)) * inner;
    return Path()
      ..moveTo(outerStart.dx, outerStart.dy)
      ..arcTo(outerRect, start, sweep, false)
      ..lineTo(innerEnd.dx, innerEnd.dy)
      ..arcTo(innerRect, end, -sweep, false)
      ..close();
  }

  static void _drawDivider(
    Canvas canvas,
    _SectorGeometry geometry,
    double angle,
  ) {
    final from = geometry.center +
        Offset(math.cos(angle), math.sin(angle)) * geometry.phaseInner;
    final to = geometry.center +
        Offset(math.cos(angle), math.sin(angle)) * geometry.dividerOuter;
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = _hudCyan.withValues(alpha: 0.72)
        ..strokeWidth = 1.4,
    );
  }

  static void _drawOuterRing(Canvas canvas, _SectorGeometry geometry) {
    final paint = Paint()
      ..color = _hudCyan.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const dash = 0.035;
    const gap = 0.032;
    var angle = -math.pi;
    while (angle < math.pi) {
      canvas.drawArc(
        Rect.fromCircle(center: geometry.center, radius: geometry.outerRing),
        angle,
        dash,
        false,
        paint,
      );
      angle += dash + gap;
    }
  }

  static void _drawCore(
    Canvas canvas,
    Offset center,
    double radius,
    int projectCount,
  ) {
    canvas.drawCircle(center, radius, Paint()..color = _hudPanel);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = _hudCyan,
    );
    _drawCenteredText(
      canvas,
      'KAI CORE',
      center.translate(0, -6),
      const TextStyle(
        color: _hudCyan,
        fontSize: 10,
        letterSpacing: 1.1,
        fontFamily: 'monospace',
      ),
    );
    _drawCenteredText(
      canvas,
      '$projectCount PROJECTS',
      center.translate(0, 8),
      const TextStyle(color: _hudInk, fontSize: 9),
    );
  }

  static void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  static void _drawArcText(
    Canvas canvas, {
    required String text,
    required Offset center,
    required double radius,
    required double startAngle,
    required double endAngle,
    required Color color,
    required double maximumFontSize,
    required double letterSpacing,
  }) {
    if (text.isEmpty || radius <= 0 || endAngle <= startAngle) return;
    final characters = text.runes.map(String.fromCharCode).toList();
    var fontSize = maximumFontSize;
    var widths = _measureCharacters(characters, fontSize, letterSpacing);
    final available = radius * (endAngle - startAngle) * 0.9;
    final measured = widths.fold<double>(0, (sum, width) => sum + width);
    if (measured > available && measured > 0) {
      fontSize = math.max(5.8, fontSize * available / measured);
      widths = _measureCharacters(characters, fontSize, letterSpacing);
    }
    final total = widths.fold<double>(0, (sum, width) => sum + width);
    final centerAngle = (startAngle + endAngle) / 2;
    final bottom = math.sin(centerAngle) > 0;
    final direction = bottom ? -1.0 : 1.0;
    var cursor = centerAngle - direction * (total / radius) / 2;

    for (var i = 0; i < characters.length; i++) {
      final angularWidth = widths[i] / radius;
      final angle = cursor + direction * angularWidth / 2;
      final position =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final painter = TextPainter(
        text: TextSpan(
          text: characters[i],
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(angle + (bottom ? -math.pi / 2 : math.pi / 2));
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
      cursor += direction * angularWidth;
    }
  }

  static List<double> _measureCharacters(
    List<String> characters,
    double fontSize,
    double letterSpacing,
  ) {
    return characters.map((character) {
      final painter = TextPainter(
        text: TextSpan(
          text: character,
          style: TextStyle(fontSize: fontSize, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width + letterSpacing;
    }).toList();
  }

  @override
  bool shouldRepaint(covariant _ProjectSectorPainter oldDelegate) {
    return oldDelegate.projects != projects || oldDelegate.selected != selected;
  }
}
