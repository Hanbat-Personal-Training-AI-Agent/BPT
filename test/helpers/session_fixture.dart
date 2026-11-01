import 'dart:async';

import 'package:bpt/core/network/api_client.dart';
import 'package:bpt/features/auth/providers/auth_provider.dart';
import 'package:bpt/models/user_model.dart';
import 'package:bpt/services/auth_service.dart';
import 'package:bpt/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserModel sessionUser(String id) => UserModel(
    id: id,
    username: id,
    name: id,
    email: '$id@example.test',
    password: '',
    avatarInitials: id,
    joinedAt: DateTime(2026));

class SessionAuthService extends AuthService {
  SessionAuthService() : super(ApiClient(baseUrl: 'https://api.example.test'));
  Completer<UserModel>? scan;
  Completer<UserModel>? profile;
  Completer<void>? deletion;
  final profileWrites = <String>[];
  final onboardingWrites = <String>[];
  String id = 'A';

  @override
  Future<UserModel> login(
      {required String email, required String password}) async {
    id = email;
    restoreAuthToken('token-$email', refreshToken: 'refresh-$email');
    return sessionUser(email);
  }

  @override
  Future<UserModel> fetchUserProfile() =>
      profile?.future ?? Future.value(sessionUser(id));

  @override
  Future<UserModel> recordBodyScan({String? sessionPath}) =>
      scan?.future ??
      Future.value(
          sessionUser(id).copyWith(lastBodyScanDate: DateTime(2026, 11, 2)));

  @override
  Future<void> deleteAccount() => deletion?.future ?? Future<void>.value();

  @override
  Future<void> saveUserData(UserModel user) async {
    profileWrites.add(user.id);
  }

  @override
  Future<void> updateOnboarding(
      {required String gender,
      required double heightCm,
      required double weightKg,
      required String workoutGoal,
      required int weeklyFrequency}) async {
    onboardingWrites.add(id);
  }
}

Future<
    ({
      AuthNotifier auth,
      SessionAuthService service,
      LocalStorageService storage
    })> sessionFixture(SharedPreferences prefs, {String id = 'A'}) async {
  final service = SessionAuthService();
  final storage = LocalStorageService(prefs);
  final auth = AuthNotifier(service, storage);
  await auth.login(id, 'password', rememberMe: true);
  return (auth: auth, service: service, storage: storage);
}
