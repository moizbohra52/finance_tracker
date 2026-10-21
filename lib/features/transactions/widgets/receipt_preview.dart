import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/data/repositories/receipt_store.dart';
import 'package:finance_tracker/domain/entities/transaction.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Where a receipt is shown from: the copy on this phone, or a signed link.
typedef _Receipt = ({Uint8List? bytes, String? link, bool pending});

/// The "Receipt" row of a transaction's details: a thumbnail that opens the
/// photo full screen. Shows nothing when the transaction has no receipt.
class ReceiptPreview extends StatefulWidget {
  const ReceiptPreview({super.key, required this.transaction});

  final Transaction transaction;

  @override
  State<ReceiptPreview> createState() => _ReceiptPreviewState();
}

class _ReceiptPreviewState extends State<ReceiptPreview> {
  late Future<_Receipt> _receipt = _load();

  /// The phone's copy first, so the user's own photos show offline.
  Future<_Receipt> _load() async {
    final ReceiptStore store = Get.find<ReceiptStore>();
    final String id = widget.transaction.id;
    final Uint8List? bytes = await store.localBytes(id);
    if (bytes != null) {
      return (bytes: bytes, link: null, pending: await store.isPending(id));
    }
    final String? path = widget.transaction.attachmentUrl;
    if (path == null) return (bytes: null, link: null, pending: false);
    return (bytes: null, link: await store.signedLink(path), pending: false);
  }

  void _retry() => setState(() {
    _receipt = _load();
  });

  /// The screen reloads the transaction after an edit or a sync; a changed
  /// row may have a new, changed or removed receipt.
  @override
  void didUpdateWidget(ReceiptPreview old) {
    super.didUpdateWidget(old);
    if (old.transaction.updatedAt != widget.transaction.updatedAt ||
        old.transaction.attachmentUrl != widget.transaction.attachmentUrl) {
      _receipt = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return FutureBuilder<_Receipt>(
      future: _receipt,
      builder: (BuildContext context, AsyncSnapshot<_Receipt> snapshot) {
        final Object? error = snapshot.error;
        final _Receipt? receipt = snapshot.data;
        final Widget content;
        if (error is NetworkFailure) {
          content = Text(
            'Receipt will show when you are online'.tr,
            style: text.bodyMedium,
          );
        } else if (error != null) {
          content = Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  "Couldn't load the receipt.".tr,
                  style: text.bodyMedium,
                ),
              ),
              TextButton(onPressed: _retry, child: Text('Retry'.tr)),
            ],
          );
        } else if (receipt == null) {
          return const SizedBox.shrink(); // Still reading the phone's copy.
        } else if (receipt.bytes == null && receipt.link == null) {
          return const SizedBox.shrink();
        } else {
          content = _Thumbnail(receipt: receipt, onRetry: _retry);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 96,
                child: Text('Receipt'.tr, style: text.bodyMedium),
              ),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.receipt, required this.onRetry});

  final _Receipt receipt;

  /// Fetches a new link, for an image that failed (for example, expired).
  final VoidCallback onRetry;

  /// [size] null is the full-screen view.
  Widget _image({double? size}) {
    final BoxFit fit = size == null ? BoxFit.contain : BoxFit.cover;
    final Uint8List? bytes = receipt.bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: fit,
        // A damaged copy on the phone: say so instead of throwing.
        errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
            Text("Couldn't load the receipt.".tr),
      );
    }
    return Image.network(
      receipt.link!,
      width: size,
      height: size,
      fit: fit,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(child: Text("Couldn't load the receipt.".tr)),
              if (size != null)
                TextButton(onPressed: onRetry, child: Text('Retry'.tr)),
            ],
          ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => Scaffold(
          appBar: AppAppBar(title: 'Receipt'.tr),
          body: InteractiveViewer(maxScale: 5, child: Center(child: _image())),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          button: true,
          label: 'Open receipt photo'.tr,
          child: InkWell(
            onTap: () => _open(context),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: _image(size: 96),
            ),
          ),
        ),
        if (receipt.pending) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Waiting to upload'.tr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
