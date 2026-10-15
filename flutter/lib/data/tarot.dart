class TarotArcana {
  const TarotArcana({
    required this.name,
    required this.keywords,
    required this.meaning,
    required this.aura,
  });

  final String name;
  final String keywords;
  final String meaning;
  final String aura;
}

const majorArcana = [
  TarotArcana(
    name: 'O Louco',
    keywords: 'início, fé, salto',
    meaning:
        'Um novo ciclo pede coragem inocente. Confie no primeiro passo sem exigir o mapa inteiro.',
    aura: 'challenge',
  ),
  TarotArcana(
    name: 'O Mago',
    keywords: 'vontade, foco, manifestação',
    meaning:
        'Você já tem as ferramentas. Canalize intenção e palavra na mesma direção.',
    aura: 'expansion',
  ),
  TarotArcana(
    name: 'A Sacerdotisa',
    keywords: 'intuição, silêncio, mistério',
    meaning:
        'A resposta não está no ruído. Recolha-se e ouça o que já sabe por dentro.',
    aura: 'introspection',
  ),
  TarotArcana(
    name: 'A Imperatriz',
    keywords: 'nutrir, criar, abundância',
    meaning:
        'Cuidar é poder. Deixe algo crescer com paciência e beleza.',
    aura: 'expansion',
  ),
  TarotArcana(
    name: 'O Imperador',
    keywords: 'estrutura, limites, autoridade',
    meaning:
        'Ordene o caos. Um limite claro protege o que você ama.',
    aura: 'expansion',
  ),
  TarotArcana(
    name: 'O Hierofante',
    keywords: 'tradição, ensino, fé',
    meaning:
        'Busque um ensinamento ou ritual que te conecte a algo maior que o ego.',
    aura: 'introspection',
  ),
  TarotArcana(
    name: 'Os Enamorados',
    keywords: 'escolha, união, valores',
    meaning:
        'Uma escolha de coração pede alinhamento, não conveniência.',
    aura: 'challenge',
  ),
  TarotArcana(
    name: 'O Carro',
    keywords: 'direção, vitória, domínio',
    meaning:
        'Tome as rédeas. O caminho se abre quando você dirige com clareza.',
    aura: 'expansion',
  ),
  TarotArcana(
    name: 'A Justiça',
    keywords: 'equilíbrio, verdade, karma',
    meaning:
        'Pese suas ações. O que você semeia pede honestidade agora.',
    aura: 'challenge',
  ),
  TarotArcana(
    name: 'O Eremita',
    keywords: 'busca, sabedoria, solitude',
    meaning:
        'Afaste-se do coro externo. Sua lanterna interior basta por hoje.',
    aura: 'introspection',
  ),
  TarotArcana(
    name: 'A Roda da Fortuna',
    keywords: 'ciclo, destino, virada',
    meaning:
        'A roda gira. Aceite a mudança; ela não é castigo, é movimento.',
    aura: 'expansion',
  ),
  TarotArcana(
    name: 'A Força',
    keywords: 'coragem suave, domínio interior',
    meaning:
        'A fera se acalma com gentileza, não com força bruta. Domine-se com amor.',
    aura: 'expansion',
  ),
  TarotArcana(
    name: 'O Enforcado',
    keywords: 'pausa, nova visão, entrega',
    meaning:
        'Pare de empurrar. Inverta o olhar e a solução aparece de outro ângulo.',
    aura: 'introspection',
  ),
  TarotArcana(
    name: 'A Morte',
    keywords: 'fim, transformação, renascimento',
    meaning:
        'Algo precisa encerrar para que o novo exista. Solte com dignidade.',
    aura: 'challenge',
  ),
  TarotArcana(
    name: 'A Temperança',
    keywords: 'alquimia, meio-termo, cura',
    meaning:
        'Misture os opostos sem pressa. A cura está no ritmo certo.',
    aura: 'introspection',
  ),
  TarotArcana(
    name: 'O Diabo',
    keywords: 'vínculo, sombra, desejo',
    meaning:
        'Olhe o apego de frente. Você pode desatar o que parece prisão.',
    aura: 'challenge',
  ),
  TarotArcana(
    name: 'A Torre',
    keywords: 'ruptura, verdade, despertar',
    meaning:
        'O que era falso desaba. Depois do estrondo, o chão é mais honesto.',
    aura: 'challenge',
  ),
  TarotArcana(
    name: 'A Estrela',
    keywords: 'esperança, fé, inspiração',
    meaning:
        'Há luz depois da tempestade. Confie e ofereça o que você é.',
    aura: 'expansion',
  ),
  TarotArcana(
    name: 'A Lua',
    keywords: 'sonho, ilusão, inconsciente',
    meaning:
        'Nem tudo que parece é. Navegue a névoa com intuição, não com pânico.',
    aura: 'introspection',
  ),
  TarotArcana(
    name: 'O Sol',
    keywords: 'vitalidade, clareza, alegria',
    meaning:
        'Permita-se brilhar sem culpa. A verdade simples aquece o caminho.',
    aura: 'expansion',
  ),
  TarotArcana(
    name: 'O Julgamento',
    keywords: 'chamado, despertar, perdão',
    meaning:
        'Um chamado interior pede que você se levante para uma versão mais verdadeira.',
    aura: 'expansion',
  ),
  TarotArcana(
    name: 'O Mundo',
    keywords: 'conclusão, integração, dança',
    meaning:
        'Um ciclo se completa. Celebre e prepare o próximo giro com gratidão.',
    aura: 'expansion',
  ),
];

TarotArcana pickDailyCard(DateTime day, String seed) {
  final key = day.year * 10000 + day.month * 100 + day.day + seed.hashCode;
  return majorArcana[key.abs() % majorArcana.length];
}
