import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';

/// Descriptor for a single step in an interactive spotlight tutorial.
class SpotlightTutorialStep {
  final int tabIndex;
  final GlobalKey? targetKey;
  final String tag;
  final String title;
  final String description;
  final List<String> bullets;
  final IconData icon;

  const SpotlightTutorialStep({
    required this.tabIndex,
    required this.targetKey,
    required this.tag,
    required this.title,
    required this.description,
    required this.icon,
    this.bullets = const [],
  });
}

/// Interactive step-by-step spotlight overlay used across the app.
///
/// Darkens the rest of the UI, keeps only [SpotlightTutorialStep.targetKey]
/// illuminated with a soft border, explains the feature calmly, and always
/// exposes an explicit Exit button.
class SpotlightTutorialOverlay extends StatefulWidget {
  final List<SpotlightTutorialStep> steps;
  final int currentTabIndex;
  final ValueChanged<int> onSwitchTab;
  final VoidCallback onExit;
  final VoidCallback onFinish;
  final Key cardKey;
  final Key exitButtonKey;
  final Key prevButtonKey;
  final Key nextButtonKey;
  final String exitLabel;
  final String finishLabel;

  const SpotlightTutorialOverlay({
    super.key,
    required this.steps,
    required this.currentTabIndex,
    required this.onSwitchTab,
    required this.onExit,
    required this.onFinish,
    this.cardKey = const Key('tutorial_card'),
    this.exitButtonKey = const Key('tutorial_exit_button'),
    this.prevButtonKey = const Key('tutorial_prev_button'),
    this.nextButtonKey = const Key('tutorial_next_button'),
    this.exitLabel = 'Salir',
    this.finishLabel = '¡Entendido, empezar!',
  });

  @override
  State<SpotlightTutorialOverlay> createState() =>
      _SpotlightTutorialOverlayState();
}

class _SpotlightTutorialOverlayState extends State<SpotlightTutorialOverlay> {
  int _stepIndex = 0;
  Rect? _targetRect;
  Rect? _previousRect;
  Timer? _remeasureTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncTabAndMeasure());
  }

  @override
  void dispose() {
    _remeasureTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SpotlightTutorialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTabIndex != widget.currentTabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureTarget());
    }
  }

  void _syncTabAndMeasure() {
    _remeasureTimer?.cancel();
    if (!mounted || widget.steps.isEmpty) return;
    final step = widget.steps[_stepIndex];
    if (widget.currentTabIndex != step.tabIndex) {
      widget.onSwitchTab(step.tabIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureTargetVisibleThenMeasure();
      });
    } else {
      _ensureTargetVisibleThenMeasure();
    }
  }

  void _ensureTargetVisibleThenMeasure({int retryAttempt = 0}) {
    if (!mounted) return;
    final targetContext = widget.steps[_stepIndex].targetKey?.currentContext;
    if (targetContext != null && Scrollable.maybeOf(targetContext) != null) {
      try {
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.25,
          duration: Duration.zero,
        );
      } catch (_) {
        // Ignore if scrollable ancestor is not ready yet.
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureTarget(retryAttempt: retryAttempt);
      });
      return;
    }
    _measureTarget(retryAttempt: retryAttempt);
  }

  void _measureTarget({int retryAttempt = 0}) {
    if (!mounted) return;
    final overlayObj = context.findRenderObject();
    final overlayBox = overlayObj is RenderBox ? overlayObj : null;
    final key = widget.steps[_stepIndex].targetKey;
    final targetContext = key?.currentContext;
    Rect? resolved;

    if (targetContext != null && overlayBox != null && overlayBox.hasSize) {
      final renderObj = targetContext.findRenderObject();
      if (renderObj is RenderBox && renderObj.hasSize) {
        final topLeft =
            renderObj.localToGlobal(Offset.zero, ancestor: overlayBox);
        final raw = (topLeft & renderObj.size).inflate(6);
        final bounds = Offset.zero & overlayBox.size;
        if (raw.overlaps(bounds)) {
          resolved = Rect.fromLTRB(
            raw.left.clamp(8.0, math.max(8.0, overlayBox.size.width - 8.0)),
            raw.top.clamp(8.0, math.max(8.0, overlayBox.size.height - 8.0)),
            raw.right.clamp(8.0, math.max(8.0, overlayBox.size.width - 8.0)),
            raw.bottom.clamp(8.0, math.max(8.0, overlayBox.size.height - 8.0)),
          );
          if (resolved.width < 12 || resolved.height < 12) {
            resolved = null;
          }
        }
      }
    }

    if (resolved != _targetRect) {
      setState(() {
        _previousRect = _targetRect;
        _targetRect = resolved;
      });
    }

    if (resolved == null && key != null && retryAttempt < 4) {
      _remeasureTimer?.cancel();
      _remeasureTimer = Timer(const Duration(milliseconds: 90), () {
        if (mounted) {
          _ensureTargetVisibleThenMeasure(retryAttempt: retryAttempt + 1);
        }
      });
    }
  }

  void _goToStep(int nextIndex) {
    _remeasureTimer?.cancel();
    final clamped = nextIndex.clamp(0, widget.steps.length - 1);
    setState(() {
      _previousRect = _targetRect;
      _stepIndex = clamped;
    });
    _syncTabAndMeasure();
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigNotifier>();
    final isSenior = config.seniorMode;
    final fontMult = isSenior ? 1.18 : 1.0;
    final step = widget.steps[_stepIndex];
    final isFirst = _stepIndex == 0;
    final isLast = _stepIndex == widget.steps.length - 1;
    final mediaPadding = MediaQuery.paddingOf(context);

    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final topSafe = mediaPadding.top + 12.0;
          final bottomSafe = mediaPadding.bottom + 12.0;
          final cardWidth = math.min(width - 28.0, 460.0);
          final sideMargin = math.max(14.0, (width - cardWidth) / 2.0);

          final rect = _targetRect;
          final double spaceBelow = rect == null
              ? 0.0
              : (height - bottomSafe) - (rect.bottom + 14.0);
          final double spaceAbove =
              rect == null ? 0.0 : (rect.top - 14.0) - topSafe;

          final bool placeBelow = rect != null &&
              (spaceBelow >= 230 ||
                  (spaceBelow >= spaceAbove && spaceBelow >= 175));
          final bool placeAbove =
              rect != null && !placeBelow && spaceAbove >= 175;

          final double cardTop = placeBelow
              ? (rect.bottom + 14.0).clamp(topSafe, math.max(topSafe, height - bottomSafe - 160.0))
              : topSafe;
          final double cardBottom = placeAbove
              ? (height - (rect.top - 14.0)).clamp(
                  bottomSafe,
                  math.max(bottomSafe, height - topSafe - 160.0),
                )
              : bottomSafe;

          final Alignment cardAlignment = placeBelow
              ? Alignment.topCenter
              : (placeAbove ? Alignment.bottomCenter : Alignment.center);

          final cardWidget = SpotlightTutorialCard(
            key: widget.cardKey,
            tag: step.tag,
            stepNumber: _stepIndex + 1,
            totalSteps: widget.steps.length,
            icon: step.icon,
            title: step.title,
            description: step.description,
            bullets: step.bullets,
            isFirst: isFirst,
            isLast: isLast,
            isSenior: isSenior,
            fontMult: fontMult,
            exitButtonKey: widget.exitButtonKey,
            prevButtonKey: widget.prevButtonKey,
            nextButtonKey: widget.nextButtonKey,
            exitLabel: widget.exitLabel,
            finishLabel: widget.finishLabel,
            onExit: widget.onExit,
            onPrevious: () => _goToStep(_stepIndex - 1),
            onNext: isLast ? widget.onFinish : () => _goToStep(_stepIndex + 1),
          );

          return Stack(
            children: [
              Positioned.fill(
                child: SpotlightBackdrop(
                  targetRect: rect,
                  previousRect: _previousRect,
                ),
              ),
              Positioned(
                left: sideMargin,
                right: sideMargin,
                top: cardTop,
                bottom: cardBottom,
                child: Align(
                  alignment: cardAlignment,
                  child: cardWidget,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Animated darkened backdrop with a smooth glowing cutout over [targetRect].
class SpotlightBackdrop extends StatelessWidget {
  final Rect? targetRect;
  final Rect? previousRect;

  const SpotlightBackdrop({
    super.key,
    required this.targetRect,
    this.previousRect,
  });

  @override
  Widget build(BuildContext context) {
    Widget paintFor(Rect? rect) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: CustomPaint(
            painter: SpotlightPainter(highlightRect: rect),
            child: const SizedBox.expand(),
          ),
        );

    if (targetRect == null) {
      return paintFor(null);
    }

    return TweenAnimationBuilder<Rect?>(
      tween: RectTween(
        begin: previousRect ?? targetRect,
        end: targetRect,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, animatedRect, _) => paintFor(animatedRect),
    );
  }
}

/// Shared clean white card explaining a single tutorial step.
class SpotlightTutorialCard extends StatelessWidget {
  final String tag;
  final int stepNumber;
  final int totalSteps;
  final IconData icon;
  final String title;
  final String description;
  final List<String> bullets;
  final bool isFirst;
  final bool isLast;
  final bool isSenior;
  final double fontMult;
  final Key exitButtonKey;
  final Key prevButtonKey;
  final Key nextButtonKey;
  final String exitLabel;
  final String finishLabel;
  final VoidCallback onExit;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const SpotlightTutorialCard({
    super.key,
    required this.tag,
    required this.stepNumber,
    required this.totalSteps,
    required this.icon,
    required this.title,
    required this.description,
    required this.bullets,
    required this.isFirst,
    required this.isLast,
    required this.isSenior,
    required this.fontMult,
    required this.exitButtonKey,
    required this.prevButtonKey,
    required this.nextButtonKey,
    required this.onExit,
    required this.onPrevious,
    required this.onNext,
    this.exitLabel = 'Salir',
    this.finishLabel = '¡Entendido, empezar!',
  });

  @override
  Widget build(BuildContext context) {
    final double progress = totalSteps > 0 ? stepNumber / totalSteps : 1.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySurface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11.5 * fontMult,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        'Paso $stepNumber de $totalSteps',
                        style: TextStyle(
                          fontSize: 12 * fontMult,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slateMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: exitButtonKey,
                  onPressed: onExit,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: Text(
                    exitLabel,
                    style: TextStyle(
                      fontSize: 13 * fontMult,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.darkSlate,
                    side: const BorderSide(color: AppTheme.borderSubtle),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size(0, isSenior ? 42 : 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppTheme.backgroundNeutral,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySurface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            icon,
                            color: AppTheme.primary,
                            size: isSenior ? 26 : 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 17.5 * fontMult,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.darkSlate,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14 * fontMult,
                        color: AppTheme.darkSlate,
                        height: 1.45,
                      ),
                    ),
                    if (bullets.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...bullets.map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  line,
                                  style: TextStyle(
                                    fontSize: 13.5 * fontMult,
                                    color: AppTheme.darkSlate,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (!isFirst) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      key: prevButtonKey,
                      onPressed: onPrevious,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(
                        'Anterior',
                        style: TextStyle(
                          fontSize: 14 * fontMult,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.darkSlate,
                        minimumSize: Size(0, isSenior ? 50 : 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    key: nextButtonKey,
                    onPressed: onNext,
                    icon: Icon(
                      isLast
                          ? Icons.check_circle_rounded
                          : Icons.arrow_forward_rounded,
                      size: 19,
                    ),
                    label: Text(
                      isLast ? finishLabel : 'Siguiente',
                      style: TextStyle(
                        fontSize: 14.5 * fontMult,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      minimumSize: Size(0, isSenior ? 50 : 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter that darkens the screen while leaving [highlightRect] clear
/// with a subtle primary glow and crisp white outline.
class SpotlightPainter extends CustomPainter {
  final Rect? highlightRect;

  const SpotlightPainter({required this.highlightRect});

  @override
  void paint(Canvas canvas, Size size) {
    final fullScreen = Path()..addRect(Offset.zero & size);
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.78);

    if (highlightRect == null) {
      canvas.drawPath(fullScreen, overlayPaint);
      return;
    }

    final rrect = RRect.fromRectAndRadius(
      highlightRect!,
      const Radius.circular(16),
    );
    final cutout = Path()..addRRect(rrect);
    final combined = Path.combine(PathOperation.difference, fullScreen, cutout);

    canvas.drawPath(combined, overlayPaint);

    final glowPaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;
    canvas.drawRRect(rrect, glowPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(SpotlightPainter oldDelegate) =>
      highlightRect != oldDelegate.highlightRect;
}
