class Friend {
  const Friend({
    required this.id,
    required this.name,
    this.email = '',
    this.zodiacSign = '',
    this.avatar = '',
  });

  final String id;
  final String name;
  final String email;
  final String zodiacSign;
  final String avatar;
}
