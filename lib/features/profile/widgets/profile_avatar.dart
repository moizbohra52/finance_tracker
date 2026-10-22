import 'dart:io';

import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
    this.border,
  });

  /// First letter of the name, shown when there is no photo.
  final String initial;

  /// Link to the photo, or null when there is none.
  final String? link;
  final double radius;

  /// Shows a progress indicator over the photo while it uploads.
  final bool busy;

  /// Optional decorative border around the avatar.
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextStyle textStyle = (radius < 24
            ? Theme.of(context).textTheme.titleSmall
            : Theme.of(context).textTheme.headlineSmall)
        ?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: radius < 24 ? radius * 0.85 : null,
          color: colors.primary,
        ) ??
        TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: radius < 24 ? radius * 0.85 : 20,
          color: colors.primary,
        );

    final Widget fallback = ColoredBox(
      color: colors.primary.withValues(alpha: 0.12),
      child: Center(
        child: initial.isEmpty
            ? Icon(
                Icons.person_rounded,
                size: radius * 1.1,
                color: colors.primary,
              )
            : Text(
                initial,
                style: textStyle,
              ),
      ),
    );
    final String? url = link;
    return Semantics(
      label: 'Profile photo'.tr,
      image: true,
      child: SizedBox.square(
        dimension: radius * 2,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipOval(
              child: url == null || url.trim().isEmpty
                  ? fallback
                  : _buildImage(url.trim(), fallback),
            ),
            if (border != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: border,
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
                      semanticsLabel: 'Uploading photo'.tr,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(String url, Widget fallback) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
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
            (BuildContext context, Object error, StackTrace? _) => fallback,
      );
    }
    final String cleanPath =
        url.startsWith('file://') ? url.replaceFirst('file://', '') : url;
    return Image.file(
      File(cleanPath),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? _) => fallback,
    );
  }
}
