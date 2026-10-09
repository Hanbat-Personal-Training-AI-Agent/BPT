import 'package:bpt/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final user = UserModel(
    id: '1',
    username: 'jihoon',
    name: '지훈',
    email: 'jihoon@bpt.app',
    password: '',
    avatarInitials: 'J',
    phone: '010-1234-5678',
    birthDate: DateTime(1998, 5, 15),
    lastBodyScanDate: DateTime(2026, 10, 9),
    joinedAt: DateTime(2026, 9, 30),
  );

  test('profile update uses the server field names and date format', () {
    final json = user.toUpdateJson();
    expect(json['phoneNumber'], '010-1234-5678');
    expect(json.containsKey('phone'), isFalse);
    expect(json['birthDate'], '1998-05-15');
    expect(json.containsKey('lastBodyScanDate'), isFalse);
    expect(json.containsKey('password'), isFalse);
  });

  test('empty phone is not sent so the saved number is kept', () {
    final json = UserModel(
      id: '1',
      username: 'jihoon',
      name: '지훈',
      email: 'jihoon@bpt.app',
      password: '',
      avatarInitials: 'J',
      joinedAt: DateTime(2026, 9, 30),
    ).toUpdateJson();
    expect(json.containsKey('phoneNumber'), isFalse);
    expect(json.containsKey('birthDate'), isFalse);
  });
}
