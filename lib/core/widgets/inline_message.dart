import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// [info] is a neutral note (privacy, tips); [notice] asks for attention
/// without being an error (e.g. notifications are off).
enum InlineMessageTone { error, success, info, notice }

/// Message shown inside a form or section. Errors and results are announced
/// to screen readers; static notes pass `announce: false`.
class InlineMessage extends StatelessWidget {
  const InlineMessage({
    super.key,
    required this.message,
    this.tone = InlineMessageTone.error,
    this.title,
    this.icon,
    this.action,
    this.announce = true,
  });

  final String message;
  final InlineMessageTone tone;

  /// Bold first line above [message].
  final String? title;

  /// Overrides the tone's default icon.
  final IconData? icon;

  /// Trailing control such as a TextButton.
  final Widget? action;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final (
      Color background,
      Color foreground,
      Color iconColor,
      IconData defaultIcon,
    ) = switch (tone) {
      InlineMessageTone.error => (
        colors.errorContainer,
        colors.onErrorContainer,
        colors.onErrorContainer,
        Icons.error_outline,
      ),
      InlineMessageTone.success => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
        colors.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      InlineMessageTone.info => (
        colors.surfaceContainerHighest.withValues(alpha: 0.6),
        colors.onSurfaceVariant,
        colors.primary,
        Icons.info_outline,
      ),
      InlineMessageTone.notice => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        colors.onTertiaryContainer,
        Icons.campaign_outlined,
      ),
    };
    final String? title = this.title;
    final Widget? action = this.action;

    return Semantics(
      liveRegion: announce,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: foreground.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: action == null
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: <Widget>[
            Icon(icon ?? defaultIcon, color: iconColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (title != null) ...<Widget>[
                    Text(
                      title,
                      style: text.labelLarge?.copyWith(
                        color: tone == InlineMessageTone.info
                            ? colors.onSurface
                            : foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                  ],
                  Text(
                    message,
                    style: (title == null ? text.bodyMedium : text.bodySmall)
                        ?.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

/// The current error of [submission], if any, with spacing below it.
class SubmitErrorMessage extends StatelessWidget {
  const SubmitErrorMessage(this.submission, {super.key});

  final SubmitState submission;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final String? error = submission.error.value;
      return error == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: InlineMessage(message: error),
            );
    });
  }
}
