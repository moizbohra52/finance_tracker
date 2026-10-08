import 'package:finance_tracker/bindings/feature_bindings.dart';
import 'package:finance_tracker/features/accounts/views/account_detail_view.dart';
import 'package:finance_tracker/features/accounts/views/account_form_view.dart';
import 'package:finance_tracker/features/accounts/views/account_list_view.dart';
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
import 'package:finance_tracker/features/budgets/views/budget_form_view.dart';
import 'package:finance_tracker/features/budgets/views/budget_list_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_detail_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_entry_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_form_view.dart';
import 'package:finance_tracker/features/contacts/views/contact_list_view.dart';
import 'package:finance_tracker/features/dashboard/views/app_shell_view.dart';
import 'package:finance_tracker/features/notifications/views/notification_center_view.dart';
import 'package:finance_tracker/features/profile/controllers/profile_controller.dart';
import 'package:finance_tracker/features/profile/views/profile_view.dart';
import 'package:finance_tracker/features/recurring/views/recurring_form_view.dart';
import 'package:finance_tracker/features/recurring/views/recurring_list_view.dart';
import 'package:finance_tracker/features/reminders/views/reminder_detail_view.dart';
import 'package:finance_tracker/features/reminders/views/reminder_form_view.dart';
import 'package:finance_tracker/features/reminders/views/reminder_list_view.dart';
import 'package:finance_tracker/features/reports/views/reports_view.dart';
import 'package:finance_tracker/features/settings/views/information_views.dart';
import 'package:finance_tracker/features/settings/views/settings_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_detail_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_form_view.dart';
import 'package:finance_tracker/features/transactions/views/transaction_list_view.dart';
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
      name: AppRoutes.about,
      page: () => const AboutView(),
      middlewares: <GetMiddleware>[AuthGuard()],
    ),
    GetPage<dynamic>(
      name: AppRoutes.privacyPolicy,
      page: () => const PolicyView(
        title: 'Privacy policy',
        paragraphs: <String>[
          'The privacy policy will be published before the app is released.',
          'Until then this page is a placeholder and not a statement of how '
              'your data is handled.',
        ],
      ),
      middlewares: <GetMiddleware>[AuthGuard()],
    ),
    GetPage<dynamic>(
      name: AppRoutes.terms,
      page: () => const PolicyView(
        title: 'Terms of service',
        paragraphs: <String>[
          'The terms of service will be published before the app is released.',
          'Until then this page is a placeholder and not a binding agreement.',
        ],
      ),
      middlewares: <GetMiddleware>[AuthGuard()],
    ),
    GetPage<dynamic>(
      name: AppRoutes.profile,
      page: () => const ProfileView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: BindingsBuilder<void>(
        () => Get.lazyPut(
          () => ProfileController(Get.find(), Get.find()),
          fenix: true,
        ),
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

    // Planning
    GetPage<dynamic>(
      name: AppRoutes.budgets,
      page: () => const BudgetListView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: BudgetBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.budgetForm,
      page: () => const BudgetFormView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: BudgetBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.recurring,
      page: () => const RecurringListView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: RecurringBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.recurringForm,
      page: () => const RecurringFormView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: RecurringBinding(),
    ),

    // Reminders and notifications
    GetPage<dynamic>(
      name: AppRoutes.reminders,
      page: () => const ReminderListView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: ReminderBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.reminderForm,
      page: () => const ReminderFormView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: ReminderBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.reminderDetail,
      page: () => const ReminderDetailView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: ReminderBinding(),
    ),
    GetPage<dynamic>(
      name: AppRoutes.notifications,
      page: () => const NotificationCenterView(),
      middlewares: <GetMiddleware>[AuthGuard()],
      binding: NotificationCenterBinding(),
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
