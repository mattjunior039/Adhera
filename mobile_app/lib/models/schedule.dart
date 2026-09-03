class Schedule {
  const Schedule({
    required this.id,
    required this.userId,
    required this.medicationId,
    required this.dayOfWeek,
    required this.timeOfDay,
    this.notes,
  });

  final int id;
  final int userId;
  final int medicationId;
  final String dayOfWeek;
  final String timeOfDay;
  final String? notes;

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      medicationId: json['medication_id'] as int,
      dayOfWeek: json['day_of_week'] as String,
      timeOfDay: json['time_of_day'] as String,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'medication_id': medicationId,
        'day_of_week': dayOfWeek,
        'time_of_day': timeOfDay,
        'notes': notes,
      };
}
