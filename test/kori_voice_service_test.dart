import 'package:bpt/services/kori_voice_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('speak tells native whether the line may cut in', () async {
    final calls = <Map>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('bpt/kori_voice'),
            (call) async {
      calls.add(call.arguments as Map);
      return null;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await KoriVoiceService.speak('무릎을 펴줘', isKo: true);
    await KoriVoiceService.speak('좋아!', isKo: true, interrupt: false);

    expect(calls.map((c) => c['interrupt']), [true, false]);
  });
}
