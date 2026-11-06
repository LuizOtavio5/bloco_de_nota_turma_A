import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Converte erros de comunicação com o Firebase em mensagens amigáveis.
String describeSyncError(Object error) {
  if (error is TimeoutException) {
    return 'Sem resposta do servidor. Verifique sua conexão.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'unavailable':
      case 'network-request-failed':
      case 'deadline-exceeded':
        return 'Sem conexão com o Firebase.';
      case 'permission-denied':
        return 'Acesso negado pelas regras de segurança do Firestore.';
      case 'unauthenticated':
        return 'Sessão expirada. Entre novamente.';
      case 'resource-exhausted':
        return 'Limite de uso do Firebase atingido. Tente mais tarde.';
    }
    return 'Erro no Firebase (${error.code}).';
  }
  return 'Não foi possível sincronizar com a nuvem.';
}
