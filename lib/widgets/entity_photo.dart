import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/external_activity.dart';
import 'package:finance_tracker/core/theme/app_tokens.dart';
import 'package:finance_tracker/core/widgets/app_app_bar.dart';
import 'package:finance_tracker/core/widgets/app_badges.dart';
import 'package:finance_tracker/core/widgets/app_list_tile.dart';
import 'package:finance_tracker/core/widgets/app_pickers.dart';
import 'package:finance_tracker/core/widgets/app_snackbar.dart';
import 'package:finance_tracker/data/repositories/photo_store.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

/// The round photo of a contact or group (PhotoStore), or its initial (or
/// [icon]) while there is none, while it loads and when it cannot load.
class EntityPhoto extends StatelessWidget {
  const EntityPhoto({
    super.key,
    required this.name,
    this.path,
    this.icon,
    this.size = AppSizes.iconBadge,
  });

  final String name;

  /// The photo's object name, or null when there is no photo.
  final String? path;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final IconData? icon = this.icon;
    final Widget fallback = icon == null
        ? IconBadge.initial(name, size: size)
        : IconBadge(icon: icon, size: size);
    final String? path = this.path;
    if (path == null || !Get.isRegistered<PhotoStore>()) return fallback;
    return FutureBuilder<File?>(
      future: Get.find<PhotoStore>().file(path),
      builder: (BuildContext context, AsyncSnapshot<File?> snapshot) {
        final File? file = snapshot.data;
        if (file == null) return fallback;
        return ClipOval(
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
                fallback,
          ),
        );
      },
    );
  }
}

/// A large [EntityPhoto] with a camera badge; a tap opens [showPhotoActions].
class EditablePhoto extends StatelessWidget {
  const EditablePhoto({
    super.key,
    required this.name,
    required this.path,
    required this.folder,
    required this.id,
    required this.save,
    this.icon,
    this.size = AppSizes.iconLarge,
  });

  final String name;
  final String? path;

  /// [PhotoStore.contacts] or [PhotoStore.groups].
  final String folder;
  final String id;

  /// Saves the new object name (null removes the photo) on the row.
  final Future<void> Function(String? path) save;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: path == null ? 'Add photo'.tr : 'Change photo'.tr,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showPhotoActions(
          context,
          name: name,
          path: path,
          folder: folder,
          id: id,
          save: save,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            EntityPhoto(name: name, path: path, icon: icon, size: size),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: EdgeInsets.all(size < 56 ? 2 : 5),
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: size < 56 ? 10 : 14,
                  color: colors.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PhotoAction { view, camera, gallery, remove }

/// View, take, choose or remove the photo of a contact or group. A new photo
/// is uploaded first (it needs the network) and then [save]d on the row; the
/// old one is deleted after.
Future<void> showPhotoActions(
  BuildContext context, {
  required String name,
  required String? path,
  required String folder,
  required String id,
  required Future<void> Function(String? path) save,
}) async {
  Widget option(
    BuildContext sheet,
    _PhotoAction action,
    IconData icon,
    String title,
  ) => AppListTile(
    leading: IconBadge(icon: icon),
    title: title,
    onTap: () => Navigator.of(sheet).pop(action),
  );

  final _PhotoAction? action = await showModalBottomSheet<_PhotoAction>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          if (path != null)
            option(
              sheet,
              _PhotoAction.view,
              Icons.zoom_in_rounded,
              'View photo'.tr,
            ),
          option(
            sheet,
            _PhotoAction.camera,
            Icons.photo_camera_outlined,
            'Take photo'.tr,
          ),
          option(
            sheet,
            _PhotoAction.gallery,
            Icons.photo_library_outlined,
            'Choose from gallery'.tr,
          ),
          if (path != null)
            option(
              sheet,
              _PhotoAction.remove,
              Icons.delete_outline_rounded,
              'Remove photo'.tr,
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final PhotoStore store = Get.find<PhotoStore>();
  switch (action) {
    case _PhotoAction.view:
      final File? file = await store.file(path!);
      if (!context.mounted) return;
      if (file == null) {
        AppSnackbar.show('The photo will show when you are online'.tr);
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => Scaffold(
            appBar: AppAppBar(title: name),
            body: InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.file(file)),
            ),
          ),
        ),
      );
    case _PhotoAction.remove:
      final bool confirmed = await confirmDestructive(
        context,
        title: 'Remove the photo?'.tr,
        message: 'You can add a new one any time.'.tr,
      );
      if (!confirmed) return;
      try {
        await save(null);
        unawaited(store.remove(path!));
        AppSnackbar.show('Photo removed'.tr);
      } on AppException catch (failure) {
        AppSnackbar.show(failure.message.tr);
      }
    case _PhotoAction.camera || _PhotoAction.gallery:
      final XFile? picked = await ExternalActivity.run(
        () => ImagePicker().pickImage(
          source: action == _PhotoAction.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          // Small and compressed: it is shown in a circle, and the bucket
          // takes at most 2 MB.
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        ),
      );
      if (picked == null || !context.mounted) return;
      final Uint8List bytes = await picked.readAsBytes();
      if (!context.mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext _) => PopScope(
            canPop: false,
            child: Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Uploading photo'.tr,
              ),
            ),
          ),
        ),
      );
      String message = 'Photo updated'.tr;
      try {
        final String uploaded = await store.upload(
          folder: folder,
          id: id,
          bytes: bytes,
          fileName: picked.name,
        );
        await save(uploaded);
        if (path != null) unawaited(store.remove(path));
      } on AppException catch (failure) {
        message = failure.message.tr;
      } finally {
        navigator.pop();
      }
      AppSnackbar.show(message);
  }
}
