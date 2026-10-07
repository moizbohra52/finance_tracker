import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:get/get.dart';

/// The persisted session is restored before runApp, so the session check is
/// immediate; the splash only covers the first frame.
class SplashController extends GetxController {
  SplashController(this._authController);

  final AuthController _authController;

  @override
  void onReady() {
    super.onReady();
    Get.offAllNamed<void>(_authController.takeStartRoute());
  }
}
