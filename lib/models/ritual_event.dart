class RitualEvent {
  const RitualEvent({
    required this.id,
    required this.title,
    required this.time,
    required this.date,
    this.duration = 30,
    this.energy,
  });

  final String id;
  final String title;
  final String time;
  final String date;
  final int duration;
  final String? energy;

  factory RitualEvent.fromDoc(String id, Map<String, dynamic> data) =>
      RitualEvent(
        id: id,
        title: data['title'] as String? ?? '',
        time: data['time'] as String? ?? '',
        date: data['date'] as String? ?? '',
        duration: (data['duration'] as num?)?.toInt() ?? 30,
        energy: data['energy'] as String?,
      );
}
