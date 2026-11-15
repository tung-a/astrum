class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.messages,
    this.updatedAt,
    this.messageCount = 0,
  });

  final String id;
  final String title;
  final List<ChatTurnStored> messages;

  /// Preenchidos so pelo historico na nuvem (etapa 10); o legado nao tem.
  final DateTime? updatedAt;
  final int messageCount;
}

class ChatTurnStored {
  const ChatTurnStored({
    required this.role,
    required this.text,
    this.id,
    this.createdAt,
  });
  final String role;
  final String text;

  /// Opcionais: so existem no historico da nuvem. `toJson` do legado nao os
  /// grava.
  final String? id;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {'role': role, 'text': text};

  factory ChatTurnStored.fromJson(Map<String, dynamic> json) => ChatTurnStored(
        role: json['role'] as String? ?? 'user',
        text: json['text'] as String? ?? '',
      );
}
