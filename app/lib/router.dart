import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/parent_home.dart';
import 'screens/splash_screen.dart';
import 'screens/teacher_home.dart';

String homeForRole(String role) {
  return switch (role) {
    'PARENT' => '/parent',
    'TEACHER' => '/teacher',
    'COUNSELOR' => '/counselor',
    'ADMIN' => '/admin',
    _ => '/',
  };
}

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    redirect: (context, state) {
      if (!session.restored) return null; // still restoring → splash
      final location = state.matchedLocation;
      final current = session.session;

      // Unauthenticated: everything goes to login.
      if (current == null) {
        return location == '/login' ? null : '/login';
      }

      // Authenticated: login/splash land on the role-specific home, and
      // another role's home is not allowed (role-based redirect). The shared
      // notifications inbox is reachable for roles that have one.
      final home = homeForRole(current.role);
      if (home == '/') {
        return home; // unknown role — unreachable with backend enum
      }
      final permitted = location == home || home == '/parent' && location == '/notifications' || home == '/teacher' && location == '/notifications';
      if (location == '/' || location == '/login' || !permitted) {
        return home;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/parent', builder: (context, state) => const ParentHome()),
      GoRoute(path: '/teacher', builder: (context, state) => const TeacherHome()),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/counselor',
        builder: (context, state) => const PlaceholderHome(role: 'counselor'),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const PlaceholderHome(role: 'admin'),
      ),
    ],
  );
});
