import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'avatar_repository.dart';

/// Circular avatar of the CURRENT user: their photo (centre-cropped) when
/// [avatarVersion] is not null and loaded, otherwise the first letter of [name].
class UserAvatar extends ConsumerWidget {
  const UserAvatar({super.key, required this.name, required this.avatarVersion, this.radius = 24});
  final String name;
  final int? avatarVersion;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = avatarVersion == null ? null : ref.watch(avatarBytesProvider(avatarVersion)).value;
    final size = radius * 2;
    return Semantics(
      label: 'Profile photo',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: bytes == null
            ? _Initial(name: name, radius: radius)
            : ClipOval(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  width: size,
                  height: size,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _Initial(name: name, radius: radius),
                ),
              ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name, required this.radius});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.greenTint),
        child: Center(
          child: Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.w900, color: AppColors.greenDark),
          ),
        ),
      );
}
