class User {
  const User({
    required this.id,
    required this.email,
    required this.fullName,
    this.phone,
  });

  final int id;
  final String email;
  final String fullName;
  final String? phone;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'phone': phone,
  };
}

class UserCreate {
  const UserCreate({required this.email, required this.fullName, this.phone});

  final String email;
  final String fullName;
  final String? phone;

  Map<String, dynamic> toJson() => {
    'email': email,
    'full_name': fullName,
    'phone': phone,
  };
}
