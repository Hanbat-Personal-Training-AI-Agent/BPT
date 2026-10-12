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

  test('marketing consent keeps its time when agreed and drops it when not',
      () {
    final fromServer = UserModel.fromJson({
      'username': 'jihoon',
      'marketingConsent': true,
      'marketingConsentAt': '2026-10-12T14:00:00',
    });
    expect(fromServer.marketingConsent, isTrue);
    // 다른 프로필 값을 저장해도 동의 시각이 지금으로 바뀌지 않게 그대로 보낸다.
    final agreed = fromServer.copyWith(name: '지훈').toUpdateJson();
    expect(agreed['marketingConsent'], isTrue);
    expect(agreed['marketingConsentAt'], '2026-10-12T14:00:00');
    final declined =
        fromServer.copyWith(marketingConsent: false).toUpdateJson();
    expect(declined['marketingConsent'], isFalse);
    expect(declined.containsKey('marketingConsentAt'), isFalse);
    // 서버 값을 모르면 보내지 않아서 서버에 저장된 값을 지킨다.
    expect(user.toUpdateJson().containsKey('marketingConsent'), isFalse);
  });
}
