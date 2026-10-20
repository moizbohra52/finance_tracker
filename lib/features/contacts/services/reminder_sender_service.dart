import 'package:decimal/decimal.dart';
import 'package:finance_tracker/core/services/external_activity.dart';
import 'package:finance_tracker/core/utils/app_formatters.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

enum ReminderSendStatus {
  success,
  noPhone,
  notInstalled,
  failed,
}

class ReminderSenderService {
  const ReminderSenderService._();

  /// Extracts multiple phone numbers if contact has comma/semicolon separated numbers.
  static List<String> parsePhoneNumbers(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String>[];
    return raw
        .split(RegExp(r'[,;/]'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  /// Cleans phone number for WhatsApp wa.me / deep links.
  /// Needs country code without '+', spaces, or leading zeroes.
  static String formatForWhatsApp(String raw, {String defaultCountryCode = '91'}) {
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    // Handle leading zeros (e.g. 09876543210 -> 9876543210)
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    // If 10 digits (standard Indian number without country code)
    if (digits.length == 10) {
      return '$defaultCountryCode$digits';
    }

    return digits;
  }

  /// Cleans phone number for native SMS app.
  static String formatForSms(String raw) {
    // Keep '+' if present, strip spaces, dashes, brackets
    final String trimmed = raw.trim();
    final bool hasPlus = trimmed.startsWith('+');
    final String digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return hasPlus ? '+$digits' : digits;
  }

  /// Pre-built template message in Hinglish / Hindi.
  static String buildHinglishMessage({
    required String contactName,
    required Decimal amount,
    required bool isReceivable,
    String? note,
  }) {
    final String formattedAmount = AppFormatters.money(amount.abs());
    final String noteText = (note != null && note.trim().isNotEmpty)
        ? '\nNote: ${note.trim()}'
        : '';

    if (isReceivable) {
      return 'Namaste $contactName ji,\n'
          'Aapka baki hisab $formattedAmount pending hai.'
          '$noteText\n'
          'Kripya samay milte hi ise clear kar dein.\n'
          'Dhanyawad!';
    } else {
      return 'Namaste $contactName ji,\n'
          'Aapka $formattedAmount ka hisab hamare paas baki hai.'
          '$noteText\n'
          'Kripya apna UPI ID ya account details share karein taaki hum payment bhej sakein.\n'
          'Dhanyawad!';
    }
  }

  /// Pre-built template message in English.
  static String buildEnglishMessage({
    required String contactName,
    required Decimal amount,
    required bool isReceivable,
    String? note,
  }) {
    final String formattedAmount = AppFormatters.money(amount.abs());
    final String noteText = (note != null && note.trim().isNotEmpty)
        ? '\nNote: ${note.trim()}'
        : '';

    if (isReceivable) {
      return 'Dear $contactName,\n'
          'This is a gentle reminder that your pending balance of $formattedAmount is due.'
          '$noteText\n'
          'Kindly clear the dues at your earliest convenience.\n'
          'Thank you!';
    } else {
      return 'Dear $contactName,\n'
          'We have an outstanding balance of $formattedAmount payable to you.'
          '$noteText\n'
          'Please share your UPI ID or bank details so we can process the payment.\n'
          'Thank you!';
    }
  }

  /// Opens WhatsApp directly with prefilled message (100% Free).
  static Future<ReminderSendStatus> sendWhatsApp({
    required String phone,
    required String message,
  }) async {
    final String cleaned = formatForWhatsApp(phone);
    if (cleaned.isEmpty) {
      return ReminderSendStatus.noPhone;
    }

    final String encodedMsg = Uri.encodeComponent(message);

    // Try direct app deep-link first
    final Uri deepLink = Uri.parse('whatsapp://send?phone=$cleaned&text=$encodedMsg');
    // Fallback to wa.me web-link which redirects straight to WhatsApp on device
    final Uri waMeLink = Uri.parse('https://wa.me/$cleaned?text=$encodedMsg');

    return ExternalActivity.run<ReminderSendStatus>(() async {
      try {
        if (await canLaunchUrl(deepLink)) {
          final bool launched = await launchUrl(
            deepLink,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return ReminderSendStatus.success;
        }

        if (await canLaunchUrl(waMeLink)) {
          final bool launched = await launchUrl(
            waMeLink,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return ReminderSendStatus.success;
        }

        return ReminderSendStatus.notInstalled;
      } catch (_) {
        return ReminderSendStatus.failed;
      }
    });
  }

  /// Opens the device default SMS messaging app with prefilled text (100% Free).
  static Future<ReminderSendStatus> sendSms({
    required String phone,
    required String message,
  }) async {
    final String cleaned = formatForSms(phone);
    if (cleaned.isEmpty) {
      return ReminderSendStatus.noPhone;
    }

    final Uri smsUri = Uri(
      scheme: 'sms',
      path: cleaned,
      queryParameters: <String, String>{
        'body': message,
      },
    );

    return ExternalActivity.run<ReminderSendStatus>(() async {
      try {
        if (await canLaunchUrl(smsUri)) {
          final bool launched = await launchUrl(
            smsUri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return ReminderSendStatus.success;
        }
        return ReminderSendStatus.failed;
      } catch (_) {
        return ReminderSendStatus.failed;
      }
    });
  }

  /// Opens the general device share sheet.
  static Future<void> shareGeneral({
    required String message,
    String? subject,
  }) async {
    await ExternalActivity.run(() async {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: subject ?? 'Payment Reminder',
        ),
      );
    });
  }
}
