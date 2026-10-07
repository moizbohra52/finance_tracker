import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';

enum NetworkStatus { unknown, online, offline }

/// Observes device network transport. An online transport does not guarantee
/// that a remote service such as Supabase is reachable.
class ConnectivityService extends GetxService {
  ConnectivityService() : _watch = _watchPlatform, _check = _checkPlatform;

  ConnectivityService.forTest({
    required Stream<NetworkStatus> Function() watch,
    required Future<NetworkStatus> Function() check,
  }) : _watch = watch,
       _check = check;

  static final Connectivity _connectivity = Connectivity();

  final Stream<NetworkStatus> Function() _watch;
  final Future<NetworkStatus> Function() _check;
  final Rx<NetworkStatus> status = NetworkStatus.unknown.obs;
  StreamSubscription<NetworkStatus>? _subscription;

  bool get isOffline => status.value == NetworkStatus.offline;

  @override
  void onInit() {
    super.onInit();
    _subscription = _watch().listen(
      (NetworkStatus value) => status.value = value,
      onError: (Object _) => status.value = NetworkStatus.unknown,
    );
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      status.value = await _check();
    } on Object {
      status.value = NetworkStatus.unknown;
    }
  }

  static Stream<NetworkStatus> _watchPlatform() =>
      _connectivity.onConnectivityChanged.map(_fromResults);

  static Future<NetworkStatus> _checkPlatform() async =>
      _fromResults(await _connectivity.checkConnectivity());

  static NetworkStatus _fromResults(List<ConnectivityResult> results) =>
      results.any(
        (ConnectivityResult result) => result != ConnectivityResult.none,
      )
      ? NetworkStatus.online
      : NetworkStatus.offline;

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}
