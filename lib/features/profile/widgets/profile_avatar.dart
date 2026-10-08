import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// Round profile photo. Shows the photo when there is a link and a fallback
/// (initial or icon) while it loads, when there is no link, and when the link
/// fails, so a broken image never shows.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.initial,
    this.link,
    this.radius = 48,
    this.busy = false,
  });

  /// First letter of the name, shown when there is no photo.
  final String initial;

  /// Link to the photo, or null when there is none.
  final String? link;
  final double radius;

  /// Shows a progress indicator over the photo while it uploads.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget fallback = ColoredBox(
      color: colors.primary.withValues(alpha: 0.12),
      child: Center(
        child: initial.isEmpty
            ? Icon(Icons.person_rounded, size: radius, color: colors.primary)
            : Text(
                initial,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
      ),
    );
    final String? url = link;
    return Semantics(
      label: 'Profile photo',
      image: true,
      child: SizedBox.square(
        dimension: radius * 2,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipOval(
              child: url == null
                  ? fallback
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      loadingBuilder:
                          (
                            BuildContext context,
                            Widget child,
                            ImageChunkEvent? progress,
                          ) => progress == null ? child : fallback,
                      errorBuilder:
                          (BuildContext context, Object error, StackTrace? _) =>
                              fallback,
                    ),
            ),
            if (busy)
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.scrim.withValues(alpha: 0.45),
                ),
                child: Center(
                  child: SizedBox.square(
                    dimension: AppSizes.iconLarge * 0.6,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: colors.onPrimary,
                      semanticsLabel: 'Uploading photo',
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
