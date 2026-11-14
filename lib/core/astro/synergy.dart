import 'zodiac.dart';

class SynergyResult {
  const SynergyResult({
    required this.title,
    required this.description,
    required this.score,
    required this.elementA,
    required this.elementB,
  });

  final String title;
  final String description;
  final int score;
  final String elementA;
  final String elementB;
}

SynergyResult getAstralSynergy(String sign1, String sign2) {
  final el1 = signElements[sign1];
  final el2 = signElements[sign2];
  if (el1 == null || el2 == null) {
    return SynergyResult(
      title: 'Energia Misteriosa',
      description:
          'Os astros ainda não revelaram a conexão completa entre esses signos.',
      score: 3,
      elementA: el1 ?? '?',
      elementB: el2 ?? '?',
    );
  }
  if (el1 == el2) {
    return SynergyResult(
      title: 'Espelhos da Alma',
      description:
          'Ambos vibram no elemento $el1. A compreensão é instantânea. Cuidado para não intensificarem os mesmos padrões.',
      score: 5,
      elementA: el1,
      elementB: el2,
    );
  }
  if ((el1 == 'Fogo' && el2 == 'Ar') || (el1 == 'Ar' && el2 == 'Fogo')) {
    return SynergyResult(
      title: 'Expansão e Movimento',
      description:
          'O Ar alimenta o Fogo. Entusiasmo, conversas longas e aventuras. Vocês se inspiram a ir mais longe.',
      score: 4,
      elementA: el1,
      elementB: el2,
    );
  }
  if ((el1 == 'Terra' && el2 == 'Água') || (el1 == 'Água' && el2 == 'Terra')) {
    return SynergyResult(
      title: 'Jardim Fértil',
      description:
          'A Água nutre a Terra. Apoio profundo, segurança e sensibilidade. Conexão com raízes fortes.',
      score: 4,
      elementA: el1,
      elementB: el2,
    );
  }
  if ((el1 == 'Fogo' && el2 == 'Água') || (el1 == 'Água' && el2 == 'Fogo')) {
    return SynergyResult(
      title: 'Vapor e Intensidade',
      description:
          'Emoção versus ação. Podem criar paixão ou conflito. A água não apaga o fogo, e o fogo não seca a água.',
      score: 3,
      elementA: el1,
      elementB: el2,
    );
  }
  if ((el1 == 'Terra' && el2 == 'Ar') || (el1 == 'Ar' && el2 == 'Terra')) {
    return SynergyResult(
      title: 'Céu e Terra',
      description:
          'O Ar sonha, a Terra constrói. Distantes no início, juntos realizam o impossível.',
      score: 3,
      elementA: el1,
      elementB: el2,
    );
  }
  return SynergyResult(
    title: 'Encontro de Forças',
    description:
        'Elementos distintos com grandes lições. A convivência exige adaptação e gera evolução.',
    score: 2,
    elementA: el1,
    elementB: el2,
  );
}
