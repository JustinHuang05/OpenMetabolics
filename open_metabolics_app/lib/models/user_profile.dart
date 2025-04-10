class UserProfile {
  final String userEmail;
  final double weight;
  final double height;
  final int age;
  final String gender;
  final String? lastUpdated;

  UserProfile({
    required this.userEmail,
    required this.weight,
    required this.height,
    required this.age,
    required this.gender,
    this.lastUpdated,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userEmail: json['user_email'] as String,
      weight: (json['weight'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      age: json['age'] as int,
      gender: json['gender'] as String,
      lastUpdated: json['last_updated'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_email': userEmail,
      'weight': weight,
      'height': height,
      'age': age,
      'gender': gender,
      'last_updated': lastUpdated ?? DateTime.now().toIso8601String(),
    };
  }
}
