class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.messages,
  });

  final String id;
  final String title;
  final List<ChatTurnStored> messages;
}

class ChatTurnStored {
  const ChatTurnStored({required this.role, required this.text});
  final String role;
  final String text;

  Map<String, dynamic> toJson() => {'role': role, 'text': text};

  factory ChatTurnStored.fromJson(Map<String, dynamic> json) => ChatTurnStored(
        role: json['role'] as String? ?? 'user',
        text: json['text'] as String? ?? '',
      );
}
