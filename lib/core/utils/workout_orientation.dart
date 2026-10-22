import 'package:flutter/services.dart';

/// 폰을 가로로 두고 하는 운동. 이 운동은 카메라 가이드 화면부터 운동이 끝날
/// 때까지(결과 화면 전까지) 화면을 가로로 보여준다.
bool isLandscapeWorkout(String exerciseId) => exerciseId == 'pushup';

/// 화면을 가로로 돌린다.
Future<void> lockLandscape() => SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

/// 앱 기본(세로)으로 되돌린다 (main.dart 와 같은 값).
Future<void> lockPortrait() => SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
