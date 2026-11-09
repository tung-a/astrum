import 'dart:math';

import '../data/astrology.dart';
import '../data/moon.dart';
import '../data/tarot.dart';

class OracleService {
  const OracleService();

  /// O oráculo responde somente com respostas locais (sem rede).
  Future<String> complete({
    required String prompt,
    String? sign,
  }) async {
    return localReply(prompt: prompt, sign: sign);
  }

  String localReply({required String prompt, String? sign}) {
    final lower = prompt.toLowerCase();
    final moon = moonFor(DateTime.now());
    final userSign = sign ?? 'Viajante';

    if (lower.contains('lua')) {
      return '${moon.emoji} Hoje a lua está **${moon.phaseName}**.\n\n${moon.guidance}\n\nPara $userSign, essa fase pede escuta do corpo e rituais simples: água, respiração e uma intenção escrita.';
    }
    if (lower.contains('amor')) {
      return 'O coração de $userSign pede honestidade, não pressa. Observe se você está amando a pessoa ou a projeção.\n\nSob a ${moon.phaseName}, conversas sinceras curam mais do que juras. Um cristal de quartzo rosa ou uma caminhada ao entardecer ajudam a baixar a guarda.';
    }
    if (lower.contains('cristal') || lower.contains('pedra')) {
      final stones = {
        'Fogo': 'cornalina ou jaspe vermelho',
        'Terra': 'jaspe paisagem ou olho de tigre',
        'Ar': 'ametista ou fluorita',
        'Água': 'água-marinha ou pedra da lua',
      };
      final el = signElements[userSign] ?? 'Ar';
      return 'Para o elemento $el de $userSign, trabalhe hoje com **${stones[el]}**.\n\nSegure a pedra na mão não dominante por 3 respirações e peça clareza, não milagres.';
    }
    if (lower.contains('energia') || lower.contains('hoje')) {
      return dailyEnergyFor(sign: userSign, moon: moon);
    }
    if (lower.contains('tarot') || lower.contains('carta')) {
      final card = pickDailyCard(DateTime.now(), prompt);
      return 'A carta que ecoa sua pergunta é **${card.name}** (${card.keywords}).\n\n${card.meaning}';
    }

    final fragments = [
      'As estrelas não mandam: elas conversam. $userSign, escute o que já está em você.',
      moon.guidance,
      'Se precisar de um ritual curto: acenda uma luz, respire 4 tempos, e escreva uma frase de gratidão.',
    ];
    fragments.shuffle(Random(prompt.hashCode));
    return fragments.join('\n\n');
  }
}
