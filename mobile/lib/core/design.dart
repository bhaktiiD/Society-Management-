// Design-system building blocks (finance-app reference style): greeting header,
// round icon buttons, gradient hero card, section headers, white list tiles and
// solid/soft highlight cards. Exported by widgets.dart.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Full-area loading indicator: a pastel building badge that "breathes" above
/// three bouncing green dots. Use instead of CircularProgressIndicator for
/// screens and lists (keep small spinners inside buttons).
/// Respects the system "remove animations" setting (shows a still version).
class AppLoader extends StatefulWidget {
  const AppLoader({super.key, this.label, this.dotsOnly = false});
  final String? label;

  /// Just the bouncing dots, for small spots inside a list or card.
  final bool dotsOnly;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _controller.isAnimating) _controller.stop();
    if (!still && !_controller.isAnimating) _controller.repeat();

    return Semantics(
      label: widget.label ?? 'Loading',
      liveRegion: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.dotsOnly) ...[
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = still ? 0.0 : _controller.value;
                  // Gentle breathing: 1.0 -> 1.08 -> 1.0
                  final scale = 1 + 0.08 * math.sin(2 * math.pi * t);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.heroStart, AppColors.heroEnd],
                        ),
                      ),
                      child: const Icon(Icons.apartment_rounded, size: 40, color: AppColors.greenDark),
                    ),
                  );
                },
              ),
              const SizedBox(height: 22),
            ],
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _Dot(phase: still ? 0 : (_controller.value - i * 0.14) % 1.0),
                    ),
                ],
              ),
            ),
            if (widget.label != null) ...[
              const SizedBox(height: 16),
              Text(
                widget.label!,
                style: const TextStyle(color: AppColors.muted, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.phase});
  final double phase; // 0..1 through one bounce cycle

  @override
  Widget build(BuildContext context) {
    // Only the first half of the cycle bounces; the rest rests on the ground.
    final lift = phase < 0.5 ? math.sin(phase * 2 * math.pi) : 0.0;
    return Transform.translate(
      offset: Offset(0, -12 * lift),
      child: Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(AppColors.greenDark, AppColors.green, lift),
        ),
      ),
    );
  }
}

/// Quick action: a soft pastel rounded square with a deeper coloured icon and
/// a label underneath. Fills the width it is given; use [QuickActionsRow] for
/// four. The label area is a fixed two lines tall so tiles line up whether the
/// label wraps or not.
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    required this.gradient,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Icon colour (an accent from [AppColors]).
  final Color color;

  /// Soft two-colour background (see [AppGradients]).
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
                boxShadow: [
                  BoxShadow(
                    color: gradient.last.withValues(alpha: 0.55),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 10),
            // One line, one size, one baseline for every tile; scaleDown only
            // kicks in for an unusually long label or very large system text.
            SizedBox(
              height: 20,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of exactly four [QuickActionTile]s, evenly spaced.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key, required this.tiles});
  final List<QuickActionTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final t in tiles) Expanded(child: t)],
    );
  }
}

/// 48dp white circle with a soft shadow, e.g. the bell / search buttons.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.showDot = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: const Color(0x1A000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: AppColors.ink, size: 22),
                if (showDot)
                  Positioned(
                    top: 12,
                    right: 13,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen header: small muted line over a big bold title, round actions on the
/// right. e.g. eyebrow "Hello," title "Bhakti".
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, this.eyebrow, required this.title, this.actions = const []});
  final String? eyebrow;
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null)
                Text(
                  eyebrow!,
                  style: const TextStyle(fontSize: 16, color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              // Shrinks a long name to fit instead of cutting it off.
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.15),
                ),
              ),
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: 10), a],
      ],
    );
  }
}

/// Big soft pastel-green card for the headline number of a screen.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.footer,
  });

  final String label; // small caption, e.g. "Total due"
  final String value; // the big figure, e.g. "₹4,570"
  final Widget? trailing; // e.g. a round button
  final Widget? footer; // extra content under the figure

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.heroStart, AppColors.heroEnd],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 15, color: AppColors.greenDark, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(value, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
                ),
              ),
              ?trailing,
            ],
          ),
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}

/// "Upcoming payment            See all" style heading.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// Round pastel badge holding an icon (list-tile leading).
class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon, {
    super.key,
    this.color = AppColors.greenDark,
    this.background = AppColors.greenTint,
    this.size = 44,
  });
  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

/// White rounded tile with soft shadow: leading badge, title + subtitle, trailing value.
class TileCard extends StatelessWidget {
  const TileCard({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Card for a horizontal "upcoming" row. [featured] = solid brand green
/// (the next one due); otherwise a soft light-gray card.
class HighlightCard extends StatelessWidget {
  const HighlightCard({
    super.key,
    required this.title,
    required this.amount,
    required this.caption,
    required this.icon,
    this.featured = false,
    this.onTap,
  });

  final String title;
  final String amount;
  final String caption; // e.g. "2 days left"
  final IconData icon;
  final bool featured;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = featured ? AppColors.green : AppColors.surface;
    final fg = featured ? AppColors.onGreen : AppColors.ink;
    return SizedBox(
      width: 170,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white,
                  child: Icon(icon, color: AppColors.greenDark, size: 22),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: fg),
                ),
                const SizedBox(height: 4),
                Text(amount, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: fg)),
                const SizedBox(height: 6),
                Text(
                  caption,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: featured ? AppColors.onGreen : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
