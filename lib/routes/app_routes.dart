abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  static const String dashboard = '/dashboard';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String changePassword = '/change-password';

  // Accounts
  static const String accounts = '/accounts';
  static const String accountForm = '/account-form';
  static const String accountDetail = '/account-detail';

  // Planning
  static const String budgets = '/budgets';
  static const String budgetForm = '/budget-form';
  static const String recurring = '/recurring';
  static const String recurringForm = '/recurring-form';

  // Reports
  static const String reports = '/reports';

  // Transactions
  static const String transactions = '/transactions';
  static const String transactionForm = '/transaction-form';
  static const String transactionDetail = '/transaction-detail';

  // Khata
  static const String contacts = '/contacts';
  static const String contactForm = '/contact-form';
  static const String contactDetail = '/contact-detail';
  static const String contactEntry = '/contact-entry';

  /// Screens for signed-out users only.
  static const Set<String> guestOnly = <String>{
    onboarding,
    login,
    register,
    forgotPassword,
  };
}
