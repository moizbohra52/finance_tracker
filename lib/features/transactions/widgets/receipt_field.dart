import 'dart:typed_data';

import 'package:finance_tracker/core/services/external_activity.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/inline_message.dart';
import 'package:finance_tracker/data/repositories/receipt_store.dart';
import 'package:finance_tracker/domain/services/avatar_rules.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

/// The receipt photo row of the transaction form: add, change or remove.
/// A picked photo is checked at once; nothing is kept until the form saves.
/// Why a picked photo cannot be a receipt, in the app language, or null.
/// Receipts follow the profile photo rules.
String? receiptPhotoProblem(String fileName, int byteLength) =>
    AvatarRules.check(fileName: fileName, byteLength: byteLength)?.message.tr;

class ReceiptField extends StatefulWidget {
  const ReceiptField({
    super.key,
    required this.existingPath,
    required this.transactionId,
    required this.onPicked,
    required this.onRemoved,
  });

  /// The saved receipt's object name, or null.
  final String? existingPath;
  final String transactionId;
  final ValueChanged<({Uint8List bytes, String fileName})?> onPicked;
  final VoidCallback onRemoved;

  @override
  State<ReceiptField> createState() => _ReceiptFieldState();
}

class _ReceiptFieldState extends State<ReceiptField> {
  Uint8List? _picked;
  bool _removed = false;
  String? _error;
  // Bytes, not a file: a replaced photo keeps its path, and the image cache
  // would show the old one.
  late final Future<Uint8List?> _saved = Get.isRegistered<ReceiptStore>()
      ? Get.find<ReceiptStore>().localBytes(widget.transactionId)
      : Future<Uint8List?>.value();

  Future<void> _choose() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('Take photo'.tr),
              onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Choose from gallery'.tr),
              onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final XFile? file;
    try {
      // The app lock must not ask again on return from the camera.
      file = await ExternalActivity.run(
        () => ImagePicker().pickImage(
          source: source,
          maxWidth: 1600,
          imageQuality: 70,
        ),
      );
    } on Exception {
      if (mounted) {
        setState(() => _error = "Couldn't open the camera or gallery.".tr);
      }
      return;
    }
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    final String? problem = receiptPhotoProblem(file.name, bytes.length);
    if (!mounted) return;
    setState(() {
      _error = problem;
      if (problem == null) {
        _picked = bytes;
        _removed = false;
      }
    });
    if (problem == null) widget.onPicked((bytes: bytes, fileName: file.name));
  }

  void _remove() {
    setState(() {
      _picked = null;
      _removed = true;
      _error = null;
    });
    widget.onPicked(null);
    widget.onRemoved();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _saved,
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> saved) {
        final Uint8List? local = _removed ? null : saved.data;
        final bool hasReceipt =
            _picked != null ||
            (!_removed && (widget.existingPath != null || local != null));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (hasReceipt)
              Row(
                children: <Widget>[
                  _Thumbnail(picked: _picked, local: local),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text('Receipt photo'.tr)),
                  TextButton(onPressed: _choose, child: Text('Change'.tr)),
                  TextButton(onPressed: _remove, child: Text('Remove'.tr)),
                ],
              )
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text('Add receipt photo'.tr),
                onPressed: _choose,
              ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              InlineMessage(message: _error!),
            ],
          ],
        );
      },
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.picked, required this.local});

  final Uint8List? picked;
  final Uint8List? local;

  @override
  Widget build(BuildContext context) {
    const double size = 56;
    const Widget placeholder = SizedBox(
      width: size,
      height: size,
      child: Icon(Icons.receipt_long_outlined),
    );
    final Uint8List? bytes = picked ?? local;
    final Widget image = bytes == null
        ? placeholder
        : Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
                placeholder,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: image,
    );
  }
}
