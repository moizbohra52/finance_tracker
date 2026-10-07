import 'package:finance_tracker/features/auth/controllers/change_password_controller.dart';
import 'package:finance_tracker/features/auth/controllers/forgot_password_controller.dart';
import 'package:finance_tracker/features/auth/controllers/login_controller.dart';
import 'package:finance_tracker/features/auth/controllers/register_controller.dart';
import 'package:finance_tracker/features/auth/controllers/reset_password_controller.dart';
import 'package:finance_tracker/features/auth/controllers/splash_controller.dart';
import 'package:finance_tracker/features/auth/views/change_password_view.dart';
import 'package:finance_tracker/features/auth/views/forgot_password_view.dart';
import 'package:finance_tracker/features/auth/views/login_view.dart';
import 'package:finance_tracker/features/auth/views/onboarding_view.dart';
import 'package:finance_tracker/features/auth/views/register_view.dart';
import 'package:finance_tracker/features/auth/views/reset_password_view.dart';
import 'package:finance_tracker/features/auth/views/splash_view.dart';
import 'package:finance_tracker/features/dashboard/views/app_shell_view.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/profile/views/profile_view.dart';
import 'package:finance_tracker/features/settings/views/settings_view.dart';
import 'package:finance_tracker/routes/app_routes.dart';
import 'package:finance_tracker/routes/route_guards.dart';
import 'package:get/get.dart';

abstract final class AppPages {
  static const String initial = AppRoutes.splash;

  static final List<GetPage<dynamic>> routes = <GetPage<dynamic>>[
    GetPage<dynamic>(
      name: AppRoutes.splash,
      page: () => const SplashView(),
      binding: BindingsBuilder<void>(() {
        Get.put(SplashController(Get.find()));
      }),
    ),

    // Signed-out only.
    GetPage<dynamic>(
      name: AppRoutes.onboarding,
      page: () => const OnboardingView(),
      middlewares: <GetMiddleware>[GuestGuard()],
    ),
    GetPage<dynamic>(
      name: AppRoutes.login,
      page: () => const LoginView(),
      middlewares: <GetMiddleware>[GuestGuard()],
      binding: BindingsBuilder<void>(
        () => Get.lazyPut(() => LoginController(Get.find())),
      ),
    ),
    GetPage<dynamic>(
      name: AppRoutes.register,
      page: () => const RegisterView(),
      middlewares: <GetMiddleware>[GuestGuard()],
      binding: BindingsBuilder<void>(
        () => Get.lazyPut(() => RegisterController(Get.find())),
      ),
    ),
    GetPage<dynamic>(
      name: AppRoutes.forgotPassword,
      page: () => const ForgotPasswordView(),
      middlewares: <GetMiddleware>[GuestGuard()],
      binding: BindingsBuilder<void>(
        () => Get.lazyPut(() => ForgotPasswordController(Get.find())),
      ),
    ),

    // Signed-in only. The reset screen runs on the recovery session.
    GetPage<dynamic>(
      name: AppRoutes.resetPassword,
      page: () => const ResetPasswordView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: BindingsBuilder<void>(
        () => Get.lazyPut(() => ResetPasswordController(Get.find())),
      ),
    ),
    GetPage<dynamic>(
      name: AppRoutes.dashboard,
      page: () => const AppShellView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: BindingsBuilder<void>(
        () => Get.lazyPut(() => ProfileController(Get.find(), Get.find())),
      ),
    ),
    GetPage<dynamic>(
      name: AppRoutes.settings,
      page: () => const SettingsView(),
      middlewares: <GetMiddleware>[AuthGuard()],
    ),
    GetPage<dynamic>(
      name: AppRoutes.profile,
      page: () => const ProfileView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: BindingsBuilder<void>(
        () => Get.lazyPut(() => ProfileController(Get.find(), Get.find())),
      ),
    ),
    GetPage<dynamic>(
      name: AppRoutes.changePassword,
      page: () => const ChangePasswordView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: BindingsBuilder<void>(
        () => Get.lazyPut(() => ChangePasswordController(Get.find())),
      ),
    ),
  ];
}
