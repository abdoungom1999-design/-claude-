import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Erreur réseau normalisée en message affichable directement dans l'UI.
class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  factory ApiException.depuisFirebaseAuth(FirebaseAuthException erreur) {
    switch (erreur.code) {
      case 'email-already-in-use':
        return ApiException('Ce numéro est déjà associé à un compte.');
      case 'weak-password':
        return ApiException('Mot de passe trop faible (8 caractères minimum).');
      case 'invalid-email':
        return ApiException('Numéro ou email invalide.');
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return ApiException('Numéro ou mot de passe incorrect.');
      case 'user-disabled':
        return ApiException('Ce compte a été désactivé.');
      case 'too-many-requests':
        return ApiException('Trop de tentatives. Réessayez dans quelques minutes.');
      case 'network-request-failed':
        return ApiException('Impossible de contacter le serveur. Vérifiez votre connexion.');
      default:
        return ApiException('Une erreur est survenue. Réessayez.');
    }
  }

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
