import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 코리 대사를 코리 목소리(ElevenLabs "manbo")로 말한다.
///
/// 합성·재생은 iOS 네이티브 `KoriSpeaker`가 하고, 여기서는 문장만 넘긴다.
/// iOS가 아니면 아무것도 하지 않는다.
class KoriVoiceService {
  KoriVoiceService._();

  static const MethodChannel _channel = MethodChannel('bpt/kori_voice');

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 지금 말하던 것을 끊고 [text]를 말한다.
  static Future<void> speak(String text, {required bool isKo}) async {
    if (!_isIOS || text.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<void>('speak', {
        'text': text,
        'language': isKo ? 'ko-KR' : 'en-US',
      });
    } on PlatformException catch (e) {
      debugPrint('[TTS] speak 실패: ${e.message}');
    }
  }

  static Future<void> stop() async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      debugPrint('[TTS] stop 실패: ${e.message}');
    }
  }
}
