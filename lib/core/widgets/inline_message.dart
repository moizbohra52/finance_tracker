import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum InlineMessageTone { error, success }

/// Message shown inside a form or section, announced to screen readers.
class InlineMessage extends StatelessWidget {
  const InlineMessage({
    super.key,
    required this.message,
    this.tone = InlineMessageTone.error,
  });

  final String message;
  final InlineMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isError = tone == InlineMessageTone.error;
    final Color background = isError
        ? colors.errorContainer
        : colors.primaryContainer;
    final Color foreground = isError
        ? colors.onErrorContainer
        : colors.onPrimaryContainer;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: foreground.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: foreground,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
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
