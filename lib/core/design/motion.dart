import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Press-and-release scale wrapper. Scales the child down to [scale] while
/// pressed and springs back on release. Light haptic feedback on tap.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final Duration duration;
  final bool haptic;

  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.duration = const Duration(milliseconds: 120),
    this.haptic = true,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  double _scale = 1.0;

  void _down(_) {
    if (widget.onTap == null) return;
    setState(() => _scale = widget.scale);
  }

  void _up(_) {
    if (widget.onTap == null) return;
    setState(() => _scale = 1.0);
  }

  void _cancel() {
    if (widget.onTap == null) return;
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _scale,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
