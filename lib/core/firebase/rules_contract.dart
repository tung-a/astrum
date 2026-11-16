/// Contrato com `firestore.rules`: constantes que o app e as regras precisam
/// compartilhar. Cada valor aponta a funcao/regra correspondente. Se mudar um
/// lado, mude o outro; `test/rules_contract_test.dart` le o arquivo de regras
/// e falha se os dois divergirem. Somente constantes (sem Flutter, sem
/// Firebase).
library;

// --- Economia
/// firestore.rules: `isCheckin` (`newStar() == oldStar() + 25`).
const int checkInReward = 25;

/// firestore.rules: `create` (`wallet == {'stardust': 500}`).
const int initialStardust = 500;

// --- Itens padrao (valem sem consultar o catalogo)
/// firestore.rules: `equippedOk` (`equipTypeOk(..., 'skin', 'skin_classic')`).
const String defaultSkinId = 'skin_classic';

/// firestore.rules: `equippedOk` (`equipTypeOk(..., 'background', 'bg_void')`).
const String defaultBackgroundId = 'bg_void';

/// firestore.rules: `initialInvOk` (`inventory == ['skin_classic', 'bg_void']`).
const List<String> defaultInventory = [defaultSkinId, defaultBackgroundId];

/// firestore.rules: `initialInvOk` (`matches('^pfp_zodiac_[a-z]+$')`).
const String zodiacAvatarPrefix = 'pfp_zodiac_';

// --- Intencoes (id -> rotulo)
/// firestore.rules: `labelOk` (notifications).
const Map<String, String> intentionLabels = {
  'luz': 'Luz',
  'coragem': 'Coragem',
  'cura': 'Cura',
  'clareza': 'Clareza',
};

// --- Catalogo
/// firestore.rules: `validItem` (`d.type in [...]`).
const List<String> catalogItemTypes = ['skin', 'background', 'profilePicture'];

// --- Papeis
/// firestore.rules: `create` (`role == 'user'`).
const String roleUser = 'user';

/// firestore.rules: `isAdmin` (`role == 'admin'`).
const String roleAdmin = 'admin';

// --- Analytics
/// firestore.rules: `analytics_events` (userId sem login).
const String anonymousUserId = 'anonymous';

/// firestore.rules: `analytics_events` (`eventName.size() <= 100`).
const int analyticsEventNameMax = 100;

// --- Limites de campo de users/{uid} (`profileShapeOk`)
const int profileNameMax = 100; // name.size() <= 100
const int profileEmailMax = 254; // optStr('email', 254)
const int profileZodiacSignMax = 30; // optStr('zodiacSign', 30)
const int profileBirthDateMax = 20; // optStr('birthDate', 20)
const int profileBirthTimeMax = 10; // optStr('birthTime', 10)
const int profileBirthPlaceMax = 200; // optStr('birthPlace', 200)
const int profileAstralMapJsonMax = 20000; // optStr('astralMapJson', 20000)
const int profileMapFieldMaxKeys =
    5; // optMap(astrologyData/dailyHoroscope/dailyTarot, 5)
const int inventoryMaxItems = 500; // inventory.size() <= 500

// --- Limites de publicProfiles/{uid} (`validPublic`)
const int publicNameMax = 100; // d.name.size() <= 100
const int publicAvatarMax = 100; // d.avatar.size() <= 100
const int emailHashLength = 64; // matches('^[0-9a-f]{64}$')

// --- Conversas do oraculo (users/{uid}/conversations, `validConv` e messages)
const int chatTitleMax = 80; // d.title.size() <= 80
const int chatMessagesMax = 500; // d.messageCount <= 500
const int chatTextMax = 10000; // data.text.size() <= 10000
const int chatSchemaVersion = 1; // d.schemaVersion == 1

// --- Amizades (friendships/{pairId}, etapa 12)
/// firestore.rules: `status == 'pending'` (create; aceitar/recusar partem dele).
const String friendshipPending = 'pending';

/// firestore.rules: `status == 'accepted'` (aceite; intencoes exigem este).
const String friendshipAccepted = 'accepted';

/// firestore.rules: `status == 'declined'` (recusa/remocao = lapide).
const String friendshipDeclined = 'declined';

/// firestore.rules: `requesterName/responderName.size() <= 100`.
const int friendshipNameMax = 100;

/// firestore.rules: `pairId(a, b)` e `pid.split('_')` (id = menor_maior).
const String friendshipIdSeparator = '_';

/// SO DO APP (nao ha regra: o Spark nao conta documentos). Maximo de pedidos
/// enviados ainda pendentes; higiene de UX, nao barreira de seguranca (R-S1).
const int maxPendingOutgoingClient = 20;
