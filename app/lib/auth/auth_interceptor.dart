import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'session.dart';

/// - Attaches `Authorization: Bearer <access>` to every request.
/// - On 401: single-flight refresh via `POST /auth/refresh`, persists the
///   rotated pair, retries the original request once.
/// - If refresh fails (revoked/reused token, deleted user): clears the
///   session, which sends the router back to login.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required SessionManager session}) : _session = session;

  final SessionManager _session;

  /// Bare client without interceptors, used only for the refresh call and
  /// the post-refresh retry (both must not re-enter this interceptor).
  static final Dio _plain = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));

  Future<void>? _refreshing;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final current = _session.session;
    if (current != null) {
      options.headers['Authorization'] = 'Bearer ${current.accessToken}';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final isAuthError = err.response?.statusCode == 401;
    final alreadyRetried =
        err.requestOptions.extra['retried_after_refresh'] == true;
    final hasSession = _session.session != null;
    if (!isAuthError || alreadyRetried || !hasSession) {
      handler.next(err);
      return;
    }

    try {
      // Single-flight: concurrent 401s share one refresh request, otherwise
      // the second rotation would be flagged as reuse and revoke the family.
      await (_refreshing ??= _refresh());
      final refreshed = _session.session;
      if (refreshed == null) {
        handler.next(err);
        return;
      }
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
      options.extra['retried_after_refresh'] = true;
      final response = await _plain.fetch<dynamic>(options);
      handler.resolve(response);
    } catch (_) {
      await _session.clear();
      handler.next(err);
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _refresh() async {
    final current = _session.session;
    if (current == null) {
      throw StateError('no session to refresh');
    }
    final response = await _plain.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refreshToken': current.refreshToken},
    );
    await _session.updateTokens(
      accessToken: response.data!['accessToken'] as String,
      refreshToken: response.data!['refreshToken'] as String,
    );
  }
}
