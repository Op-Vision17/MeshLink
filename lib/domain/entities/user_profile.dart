class UserProfile {
  final String displayName;
  final int avatarIndex;
  final String statusMessage;

  const UserProfile({
    required this.displayName,
    required this.avatarIndex,
    this.statusMessage = 'Available on MeshLink',
  });

  UserProfile copyWith({
    String? displayName,
    int? avatarIndex,
    String? statusMessage,
  }) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
      avatarIndex: avatarIndex ?? this.avatarIndex,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'avatarIndex': avatarIndex,
        'statusMessage': statusMessage,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        displayName: json['displayName'] as String? ?? 'Me',
        avatarIndex: json['avatarIndex'] as int? ?? 0,
        statusMessage: json['statusMessage'] as String? ?? 'Available on MeshLink',
      );
}
