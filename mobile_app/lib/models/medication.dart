class Medication {
  const Medication({
    required this.id,
    required this.userId,
    required this.name,
    this.dosage,
    this.instructions,
  });

  final int id;
  final int userId;
  final String name;
  final String? dosage;
  final String? instructions;

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      name: json['name'] as String,
      dosage: json['dosage'] as String?,
      instructions: json['instructions'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'dosage': dosage,
        'instructions': instructions,
      };
}
