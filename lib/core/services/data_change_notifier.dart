import 'package:get/get.dart';

/// Tells open screens that finance data changed, so tabs that show the same
/// records (home, lists, khata) reload after any write without knowing about
/// each other.
class DataChangeNotifier extends GetxService {
  final RxInt version = 0.obs;

  void markChanged() => version.value++;
}
