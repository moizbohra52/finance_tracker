import 'package:finance_tracker/features/reports/views/reports_view.dart';
import 'package:finance_tracker/bindings/feature_bindings.dart';
import 'package:finance_tracker/features/contacts/views/contact_detail_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_entry_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_form_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_list_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_detail_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_form_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_list_view.dart';
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
import 'package:finance_tracker/features/accounts/views/account_detail_view.dart';
import 'package:finance_tracker/features/accounts/views/account_form_view.dart';
import 'package:finance_tracker/features/accounts/views/account_list_view.dart';
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
      binding: ShellBinding(),
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
    // Accounts
    GetPage<dynamic>(
      name: AppRoutes.accounts,
      page: () => const AccountListView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: AccountBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.accountForm,
      page: () => const AccountFormView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: AccountBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.accountDetail,
      page: () => const AccountDetailView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: AccountDetailBinding(),
    ),

    // Reports
    GetPage<dynamic>(
      name: AppRoutes.reports,
      page: () => const ReportsPage(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: ReportsBinding(),
    ),

    // Transactions
    GetPage<dynamic>(
      name: AppRoutes.transactions,
      page: () => const TransactionListView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: TransactionBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.transactionForm,
      page: () => const TransactionFormView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: TransactionBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.transactionDetail,
      page: () => const TransactionDetailView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: TransactionDetailBinding(),
    ),

    // Khata
    GetPage<dynamic>(
      name: AppRoutes.contacts,
      page: () => const ContactListView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: ContactBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.contactForm,
      page: () => const ContactFormView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: ContactBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.contactDetail,
      page: () => const ContactDetailView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: ContactDetailBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.contactEntry,
      page: () => const ContactEntryView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: ContactBinding(),
    ),
  ];
}
