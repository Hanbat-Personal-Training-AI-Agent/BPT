import 'dart:convert';

class UserModel {
  final String id;
  final String username;
  final String name;
  final String email;
  final String password;
  final String avatarInitials;
  final DateTime? birthDate;
  final double weightKg;
  final double heightCm;
  final String? gender;
  final String? workoutGoal;
  final String? phone;
  final int totalWorkouts;
  final int streakDays;
  final DateTime joinedAt;

  const UserModel({
    required this.id,
    required this.username,
    required this.name,
    required this.email,
    required this.password,
    required this.avatarInitials,
    this.birthDate,
    this.weightKg = 0,
    this.heightCm = 0,
    this.gender,
    this.workoutGoal,
    this.phone,
    this.totalWorkouts = 0,
    this.streakDays = 0,
    required this.joinedAt,
  });

  int get age {
    if (birthDate == null) return 0;
    final today = DateTime.now();
    int a = today.year - birthDate!.year;
    if (today.month < birthDate!.month ||
        (today.month == birthDate!.month && today.day < birthDate!.day)) {
      a--;
    }
    return a < 0 ? 0 : a;
  }

  UserModel copyWith({
    String? username,
    String? name,
    String? email,
    String? password,
    String? avatarInitials,
    DateTime? birthDate,
    bool clearBirthDate = false,
    double? weightKg,
    double? heightCm,
    String? gender,
    String? workoutGoal,
    String? phone,
    int? totalWorkouts,
    int? streakDays,
  }) {
    return UserModel(
      id: id,
      username: username ?? this.username,
      name: name ?? this.name,
      email: email ?? this.email,
      password: password ?? this.password,
      avatarInitials: avatarInitials ?? this.avatarInitials,
      birthDate: clearBirthDate ? null : (birthDate ?? this.birthDate),
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      gender: gender ?? this.gender,
      workoutGoal: workoutGoal ?? this.workoutGoal,
      phone: phone ?? this.phone,
      totalWorkouts: totalWorkouts ?? this.totalWorkouts,
      streakDays: streakDays ?? this.streakDays,
      joinedAt: joinedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'email': email,
        'password': password,
        'avatarInitials': avatarInitials,
        'birthDate': birthDate?.toIso8601String(),
        'weightKg': weightKg,
        'heightCm': heightCm,
        'gender': gender,
        'workoutGoal': workoutGoal,
        'phone': phone,
        'totalWorkouts': totalWorkouts,
        'streakDays': streakDays,
        'joinedAt': joinedAt.toIso8601String(),
      };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String? ?? '',
        username: json['username'] as String? ?? '',
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        password: json['password'] as String? ?? '',
        avatarInitials: json['avatarInitials'] as String? ?? 'U',
        birthDate: json['birthDate'] != null
            ? DateTime.tryParse(json['birthDate'].toString())
            : null,
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
        heightCm: (json['heightCm'] as num?)?.toDouble() ?? 0,
        gender: json['gender'] as String?,
        workoutGoal: json['workoutGoal'] as String?,
        phone: json['phone'] as String?,
        totalWorkouts: (json['totalWorkouts'] as num?)?.toInt() ?? 0,
        streakDays: (json['streakDays'] as num?)?.toInt() ?? 0,
        joinedAt: json['joinedAt'] != null
            ? DateTime.tryParse(json['joinedAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );

  String toJsonString() => jsonEncode(toJson());
  factory UserModel.fromJsonString(String s) =>
      UserModel.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
