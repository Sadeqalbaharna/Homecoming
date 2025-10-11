import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app_shell.dart';                           // ✅ same folder
import '../features/home/presentation/home_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) => '/home',
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const AppShell(child: HomeScreen()),
      ),
      // Add more routes later if you like
    ],
  );
});
