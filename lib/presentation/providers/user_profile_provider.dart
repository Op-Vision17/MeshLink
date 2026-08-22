import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/user_profile.dart';
import 'mesh_provider.dart';

class UserProfileNotifier extends StateNotifier<UserProfile> {
  final Ref _ref;

  UserProfileNotifier(this._ref)
      : super(const UserProfile(displayName: 'MeshUser', avatarIndex: 0)) {
    _loadProfile();
  }

  Future<File> get _profileFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user_profile.json');
  }

  Future<void> _loadProfile() async {
    try {
      final file = await _profileFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        final profile = UserProfile.fromJson(map);
        state = profile;
        _syncToNative(profile);
      } else {
        // Auto-generate friendly default name
        final defaultName = 'User_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
        final initial = UserProfile(displayName: defaultName, avatarIndex: 0);
        state = initial;
        await _saveProfile(initial);
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  Future<void> updateProfile({String? displayName, int? avatarIndex, String? statusMessage}) async {
    final updated = state.copyWith(
      displayName: displayName,
      avatarIndex: avatarIndex,
      statusMessage: statusMessage,
    );
    state = updated;
    await _saveProfile(updated);
    await _syncToNative(updated);
  }

  Future<void> _saveProfile(UserProfile profile) async {
    try {
      final file = await _profileFile;
      await file.writeAsString(jsonEncode(profile.toJson()));
    } catch (e) {
      debugPrint('Error saving user profile: $e');
    }
  }

  Future<void> _syncToNative(UserProfile profile) async {
    try {
      final meshRepo = _ref.read(meshRepositoryProvider);
      await meshRepo.updateUserProfile(profile.displayName, profile.avatarIndex);
      debugPrint('Synced profile to native: ${profile.displayName} (Avatar ${profile.avatarIndex})');
    } catch (e) {
      debugPrint('Error syncing profile to native mesh engine: $e');
    }
  }
}

final userProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
  return UserProfileNotifier(ref);
});
