import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:astrum/features/auth/domain/sign_up_data.dart';
import 'package:astrum/features/auth/presentation/auth_providers.dart';

/// Rascunho do cadastro entre as duas telas. Vive so em memoria (nunca em
/// go_router extra, disco ou state restoration); a senha e sensivel.
@immutable
class SignUpDraft {
  const SignUpDraft({
    required this.name,
    required this.email,
    required this.password,
  });

  final String name;
  final String email;
  final String password;

  @override
  bool operator ==(Object other) =>
      other is SignUpDraft &&
      other.name == name &&
      other.email == email &&
      other.password == password;

  @override
  int get hashCode => Object.hash(name, email, password);

  @override
  String toString() => 'SignUpDraft(email: $email, password: ***)';
}

class SignUpState {
  const SignUpState({this.draft, this.inFlight = false});
  final SignUpDraft? draft;
  final bool inFlight;
}

class SignUpController extends Notifier<SignUpState> {
  @override
  SignUpState build() => const SignUpState();

  void start(SignUpDraft draft) => state = SignUpState(draft: draft);

  void clear() => state = const SignUpState();

  /// Chama AuthRepository.register mantendo inFlight durante a chamada,
  /// independente do ciclo de vida do widget. Sucesso: limpa tudo. Falha:
  /// solta o flag, mantem o rascunho (retentar sem redigitar) e relanca
  /// AuthException. Retorna true se o cadastro ocorreu; false se nada foi
  /// enviado (sem rascunho ou ja em andamento).
  Future<bool> submit({
    required String birthDate,
    required String birthTime,
    required String birthPlace,
    required String zodiacSign,
  }) async {
    final draft = state.draft;
    if (draft == null || state.inFlight) return false;
    state = SignUpState(draft: draft, inFlight: true);
    try {
      await ref.read(authRepositoryProvider).register(SignUpData(
            name: draft.name,
            email: draft.email,
            password: draft.password,
            birthDate: birthDate,
            birthTime: birthTime,
            birthPlace: birthPlace,
            zodiacSign: zodiacSign,
          ));
      state = const SignUpState();
      return true;
    } finally {
      // Qualquer saida (inclusive excecao inesperada) solta o flag, para o
      // router nunca ficar preso em /welcome.
      if (state.inFlight) state = SignUpState(draft: draft);
    }
  }
}

final signUpControllerProvider =
    NotifierProvider<SignUpController, SignUpState>(SignUpController.new);
