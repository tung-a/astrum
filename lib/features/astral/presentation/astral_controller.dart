import 'package:astrum/core/astro/natal_chart.dart';
import 'package:astrum/features/astral/domain/birth_datetime.dart';
import 'package:astrum/features/profile/domain/app_user.dart';
import 'package:astrum/features/profile/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final astralControllerProvider =
    NotifierProvider<AstralController, void>(AstralController.new);

/// Calculo e gravacao do mapa astral (sem estado; sem guarda de reentrada,
/// como era na tela).
class AstralController extends Notifier<void> {
  @override
  void build() {}

  /// Retorna false quando a data de nascimento do [profile] e invalida (a tela
  /// avisa o usuario); senao calcula o mapa e grava, e retorna true.
  Future<bool> calculate(AppUser profile) async {
    final birth = birthDateTimeOf(
      birthDate: profile.birthDate,
      birthTime: profile.birthTime,
    );
    if (birth == null) return false;
    final computed =
        computeNatalChart(birth: birth, birthPlace: profile.birthPlace);
    await ref
        .read(profileRepositoryProvider)
        .saveAstralMap(profile.uid, computed);
    return true;
  }
}
