import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'auth/auth_interceptor.dart';
import 'auth/auth_repository.dart';
import 'auth/session.dart';
import 'config/api_config.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final sessionProvider = Provider<SessionManager>(
  (ref) => SessionManager(ref.watch(tokenStoreProvider)),
);

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
  dio.interceptors.add(AuthInterceptor(session: ref.watch(sessionProvider)));
  return dio;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dioProvider)),
);

final authControllerProvider = Provider<AuthController>(
  (ref) => AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(sessionProvider),
  ),
);
