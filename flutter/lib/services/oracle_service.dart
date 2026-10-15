import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../data/astrology.dart';
import '../data/moon.dart';
import '../data/tarot.dart';

class ChatTurn {
  const ChatTurn({required this.role, required this.text});

  /// `user` or `model`
  final String role;
  final String text;
}

class OracleService {
  OracleService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const systemInstruction =
      'Você é o Oráculo do Astrum, guia místico experiente em astrologia, '
      'cristais, tarot, fases da lua e energias sutis. '
      'Ajude a pessoa a encontrar equilíbrio e autoconhecimento. '
      'Responda com empatia, em português do Brasil, linguagem acolhedora e levemente esotérica. '
      'Não invente consultas médicas ou financeiras. Seja breve (até 3 parágrafos) salvo se pedirem mais.';

  Future<String> complete({
    required String prompt,
    List<ChatTurn> history = const [],
    String? sign,
  }) async {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _systemWithSign(sign)},
      for (final turn in history)
        {
          'role': turn.role == 'model' ? 'assistant' : 'user',
          'content': turn.text,
        },
      {'role': 'user', 'content': prompt},
    ];

    if (Env.hasGroq) {
      final groq = await _openAiCompatible(
        uri: Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${Env.groqApiKey}',
          'Content-Type': 'application/json',
        },
        body: {
          'model': 'llama-3.3-70b-versatile',
          'temperature': 0.9,
          'max_tokens': 700,
          'messages': messages,
        },
      );
      if (groq != null) return groq;
    }

    final pollinations = await _openAiCompatible(
      uri: Uri.parse('https://text.pollinations.ai/openai'),
      headers: const {'Content-Type': 'application/json'},
      body: {
        'model': 'openai',
        'messages': messages,
      },
    );
    if (pollinations != null) return pollinations;

    return localReply(prompt: prompt, sign: sign);
  }

  String _systemWithSign(String? sign) {
    if (sign == null || sign.isEmpty) return systemInstruction;
    return '$systemInstruction O signo solar da pessoa é $sign.';
  }

  Future<String?> _openAiCompatible({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final message = choices.first['message'];
          final content = message is Map ? message['content'] : null;
          if (content is String && content.trim().isNotEmpty) {
            return content.trim();
          }
        }
      }
      if (decoded is String && decoded.trim().isNotEmpty) return decoded.trim();
    } catch (_) {
      return null;
    }
    return null;
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
