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

  /// Screens for signed-out users only.
  static const Set<String> guestOnly = <String>{
    onboarding,
    login,
    register,
    forgotPassword,
  };
}
