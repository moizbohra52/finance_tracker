import 'package:finance_tracker/features/auth/controllers/auth_controller.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// Sends signed-out users to sign in.
class AuthGuard extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) =>
      Get.find<AuthController>().isSignedIn
      ? null
      : const RouteSettings(name: AppRoutes.login);
}

/// Keeps signed-in users out of the onboarding and sign-in screens.
class GuestGuard extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) =>
      Get.find<AuthController>().isSignedIn
      ? const RouteSettings(name: AppRoutes.dashboard)
      : null;
}
