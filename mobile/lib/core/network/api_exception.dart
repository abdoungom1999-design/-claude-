import 'package:dio/dio.dart';

/// Erreur réseau normalisée en message affichable directement dans l'UI.
class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  factory ApiException.depuisDio(DioException erreur) {
    switch (erreur.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return ApiException(
          'Impossible de contacter le serveur. Vérifiez votre connexion.',
        );
      default:
        break;
    }

    final donnees = erreur.response?.data;
    if (donnees is Map && donnees['message'] != null) {
      final message = donnees['message'];
      if (message is List && message.isNotEmpty) {
        return ApiException(message.first.toString());
      }
      return ApiException(message.toString());
    }

    switch (erreur.response?.statusCode) {
      case 401:
        return ApiException('Session expirée, reconnectez-vous.');
      case 403:
        return ApiException('Accès refusé.');
      case 404:
        return ApiException('Ressource introuvable.');
      case 409:
        return ApiException('Ce compte existe déjà.');
      default:
        return ApiException('Une erreur est survenue. Réessayez.');
    }
  }

  @override
  String toString() => message;
}
