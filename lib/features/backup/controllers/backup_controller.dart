import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:finance_tracker/core/services/backup_service.dart';
import 'package:finance_tracker/core/services/data_change_notifier.dart';
import 'package:finance_tracker/core/services/file_sharing_service.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/datasources/local/app_database.dart';
import 'package:finance_tracker/data/repositories/auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class BackupController extends GetxController {
  BackupController({
    required this.database,
    required this.dataChangeNotifier,
    this.authRepository,
    this.backupService = const BackupService(),
    this.sharingService = const FileSharingService(),
  });

  final AppDatabase database;
  final DataChangeNotifier dataChangeNotifier;
  final AuthRepository? authRepository;
  final BackupService backupService;
  final FileSharingService sharingService;

  final RxBool isCreatingBackup = false.obs;
  final RxBool isRestoring = false.obs;
  final RxString statusMessage = ''.obs;

  /// Creates a complete JSON backup of the user's data and triggers platform share sheet.
  Future<void> createBackupAndShare() async {
    if (isCreatingBackup.value) return;
    isCreatingBackup.value = true;
    statusMessage.value = 'Creating secure backup...';

    try {
      final String? userId = authRepository?.currentUserId;
      final Map<String, dynamic> backupPayload = await backupService
          .createBackup(database, userId: userId);

      final String timeStamp = DateFormat(
        'yyyyMMdd_HHmmss',
      ).format(DateTime.now());
      final String fileName = 'finance_tracker_backup_$timeStamp.json';

      // Pretty print JSON in compute isolate to avoid UI freeze
      final String jsonString = await compute(_formatJson, backupPayload);

      statusMessage.value = 'Preparing file for sharing...';
      await sharingService.saveAndShareString(
        fileName: fileName,
        content: jsonString,
        mimeType: 'application/json',
        subject: 'Finance Tracker Backup ($timeStamp)',
      );

      final Map<String, dynamic>? meta =
          backupPayload['metadata'] as Map<String, dynamic>?;
      final int totalRecords = (meta?['total_records'] as num?)?.toInt() ?? 0;
      AppSnackbar.show('Backup created successfully ($totalRecords records).');
    } catch (e, stack) {
      debugPrint('Backup error: $e\n$stack');
      AppSnackbar.show('Failed to create backup: $e');
    } finally {
      isCreatingBackup.value = false;
      statusMessage.value = '';
    }
  }

  /// Opens file picker for the user to select a JSON backup file.
  Future<BackupValidationResult?> pickAndValidateBackup() async {
    try {
      final PlatformFile? file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );

      if (file == null) {
        return null;
      }

      final String content = await file.xFile.readAsString();
      final BackupValidationResult validation = backupService.validateBackup(
        content,
      );
      return validation;
    } catch (e) {
      debugPrint('File pick / validation error: $e');
      AppSnackbar.show('Error reading file: $e');
      return null;
    }
  }

  /// Executes restoration of validated backup into SQLite database.
  Future<bool> executeRestore({
    required BackupValidationResult validationResult,
    required bool replaceExisting,
  }) async {
    if (validationResult.data == null) {
      AppSnackbar.show('Invalid backup data.');
      return false;
    }

    isRestoring.value = true;
    statusMessage.value = 'Restoring data...';

    try {
      final String? userId = authRepository?.currentUserId;
      final RestoreResult result = await backupService.restoreBackup(
        database,
        validationResult.data!,
        replaceExisting: replaceExisting,
        userId: userId,
      );

      if (result.success) {
        // Trigger reactive updates across entire app
        dataChangeNotifier.markChanged();

        AppSnackbar.show(
          'Restored ${result.totalRestored} records successfully!',
        );
        return true;
      } else {
        AppSnackbar.show(result.errorMessage ?? 'Restore failed.');
        return false;
      }
    } catch (e, stack) {
      debugPrint('Restore execution error: $e\n$stack');
      AppSnackbar.show('Failed to restore data: $e');
      return false;
    } finally {
      isRestoring.value = false;
      statusMessage.value = '';
    }
  }
}

String _formatJson(Map<String, dynamic> data) {
  return const JsonEncoder.withIndent('  ').convert(data);
}
