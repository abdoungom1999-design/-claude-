import 'package:dio/dio.dart';
import '../config/api_config.dart';
import 'token_storage.dart';

/// Client HTTP unique de l'application, avec injection automatique du
/// token JWT et rafraîchissement transparent en cas d'expiration (401).
class ApiClient {
  factory ApiClient() => _instance;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    _dio.interceptors.add(_AuthInterceptor(_dio));
  }

  static final ApiClient _instance = ApiClient._internal();

  late final Dio _dio;

  Dio get dio => _dio;
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._dio);

  final Dio _dio;
  final _tokenStorage = TokenStorage();
  bool _rafraichissementEnCours = false;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException erreur,
    ErrorInterceptorHandler handler,
  ) async {
    final requete = erreur.requestOptions;
    final estAppelDeRefresh = requete.path.contains('/auth/refresh');

    if (erreur.response?.statusCode != 401 ||
        estAppelDeRefresh ||
        _rafraichissementEnCours) {
      return handler.next(erreur);
    }

    _rafraichissementEnCours = true;
    try {
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken == null) {
        await _tokenStorage.effacerTokens();
        return handler.next(erreur);
      }

      final reponse = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final nouveauAccessToken = reponse.data['accessToken'] as String;
      final nouveauRefreshToken = reponse.data['refreshToken'] as String;
      await _tokenStorage.enregistrerTokens(
        accessToken: nouveauAccessToken,
        refreshToken: nouveauRefreshToken,
      );

      requete.headers['Authorization'] = 'Bearer $nouveauAccessToken';
      final reponseRetry = await _dio.fetch(requete);
      handler.resolve(reponseRetry);
    } catch (_) {
      await _tokenStorage.effacerTokens();
      handler.next(erreur);
    } finally {
      _rafraichissementEnCours = false;
    }
  }
}
