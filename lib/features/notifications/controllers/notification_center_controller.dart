import 'package:finance_tracker/core/errors/app_exception.dart';
import 'package:finance_tracker/core/services/notification_coordinator.dart';
import 'package:finance_tracker/core/utils/submit_state.dart';
import 'package:finance_tracker/data/repositories/notification_repository.dart';
import 'package:finance_tracker/domain/entities/app_notification.dart';
import 'package:finance_tracker/features/notifications/notification_target.dart';
import 'package:get/get.dart';

/// The notification center: a paged list of stored notifications, the unread
/// badge, mark-read, and opening the screen a notification is about.
class NotificationCenterController extends GetxController {
  NotificationCenterController(this._repository, this._coordinator);

  final NotificationRepository _repository;
  final NotificationCoordinator _coordinator;

  static const int pageSize = 30;

  final RxList<AppNotification> items = <AppNotification>[].obs;
  final RxInt unread = 0.obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = false.obs;
  final RxnString error = RxnString();
  final SubmitState action = SubmitState();

  @override
  void onInit() {
    super.onInit();
    load();
    ever<int>(_coordinator.centerVersion, (_) => load(silent: true));
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    error.value = null;
    try {
      final List<AppNotification> page = await _repository.getPage(
        limit: pageSize,
      );
      items.assignAll(page);
      hasMore.value = page.length == pageSize;
      unread.value = await _repository.unreadCount();
    } on AppException catch (failure) {
      if (!silent || items.isEmpty) error.value = failure.message;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      final List<AppNotification> page = await _repository.getPage(
        limit: pageSize,
        offset: items.length,
      );
      items.addAll(page);
      hasMore.value = page.length == pageSize;
    } on AppException catch (failure) {
      error.value = failure.message;
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<bool> markRead(AppNotification notification) async {
    if (notification.isRead) return true;
    return action.run(() async {
      await _repository.markRead(notification.id);
      final int i = items.indexWhere(
        (AppNotification n) => n.id == notification.id,
      );
      if (i >= 0) items[i] = notification.markedRead(DateTime.now());
      if (unread.value > 0) unread.value--;
    });
  }

  Future<bool> markAllRead() => action.run(() async {
    await _repository.markAllRead();
    final DateTime now = DateTime.now();
    items.assignAll(items.map((AppNotification n) => n.markedRead(now)));
    unread.value = 0;
  });

  /// Marks [notification] read and opens what it is about. A failure to mark
  /// it read must not stop the user from getting there.
  Future<void> open(AppNotification notification) async {
    await markRead(notification);
    final NotificationTarget target = NotificationTarget.resolve(
      notification.type,
      notification.referenceId,
    );
    if (target.route != Get.currentRoute) {
      await Get.toNamed<void>(target.route, arguments: target.argument);
    }
  }
}
