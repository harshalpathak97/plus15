import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';

class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(1.0 + 2.0 * _controller.value, 0),
              colors: isDark
                  ? [
                      AppPalette.cardDark,
                      AppPalette.borderDark,
                      AppPalette.cardDark,
                    ]
                  : [
                      AppPalette.borderLight,
                      const Color(0xFFF1F3F9),
                      AppPalette.borderLight,
                    ],
            ),
          ),
        );
      },
    );
  }
}

class ShimmerList extends StatelessWidget {
  final int count;

  const ShimmerList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const ShimmerLoading(width: 48, height: 48, borderRadius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerLoading(height: 14, width: 120 + (i * 20).toDouble()),
                  const SizedBox(height: 8),
                  const ShimmerLoading(height: 10, width: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
