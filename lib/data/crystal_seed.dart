/// Cristal inicial da colecao `cristais_propriedades`.
typedef CrystalSeed = ({
  String id,
  String name,
  String description,
  String focus,
});

const initialCrystals = <CrystalSeed>[
  (
    id: 'ametista',
    name: 'Ametista - Transmutação',
    description:
        'Pedra de proteção e elevação espiritual, indicada para meditação.',
    focus: 'Espiritualidade',
  ),
  (
    id: 'quartzo-rosa',
    name: 'Quartzo Rosa - Amor Incondicional',
    description: 'Pedra associada ao amor, à paz e à cura interior.',
    focus: 'Emoções',
  ),
  (
    id: 'citrino',
    name: 'Citrino - Prosperidade',
    description: 'Pedra solar ligada à abundância e à prosperidade.',
    focus: 'Carreira/Finanças',
  ),
  (
    id: 'olho-de-tigre',
    name: 'Olho de Tigre - Proteção e Foco',
    description: 'Ajuda a encontrar clareza, foco e discernimento.',
    focus: 'Estudo/Foco',
  ),
  (
    id: 'turmalina-negra',
    name: 'Turmalina Negra - Escudo',
    description: 'Pedra tradicionalmente associada à proteção energética.',
    focus: 'Proteção',
  ),
  (
    id: 'sodalita',
    name: 'Sodalita - Intuição e Mente',
    description: 'Associada à clareza mental e ao pensamento objetivo.',
    focus: 'Intelecto',
  ),
  (
    id: 'quartzo-transparente',
    name: 'Quartzo Transparente - Amplificador',
    description: 'Cristal associado à clareza e à amplificação de intenções.',
    focus: 'Clareza',
  ),
  (
    id: 'jaspe-vermelho',
    name: 'Jaspe Vermelho - Vitalidade',
    description: 'Pedra associada à vitalidade e à coragem.',
    focus: 'Energia Física',
  ),
];
