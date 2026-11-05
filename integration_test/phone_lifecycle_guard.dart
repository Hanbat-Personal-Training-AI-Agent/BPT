import 'package:flutter/widgets.dart';

/// Observes the real OS/binding lifecycle. Never injects or overrides a state.
class PhoneLifecycleGuard with WidgetsBindingObserver {
  PhoneLifecycleGuard() {
    WidgetsBinding.instance.addObserver(this);
    _record(WidgetsBinding.instance.lifecycleState);
  }
  final List<Map<String, Object?>> events = [];
  bool _running = false;
  bool _interrupted = false;
  void _record(AppLifecycleState? state) {
    events.add(
        {'state': state?.name, 'at': DateTime.now().toUtc().toIso8601String()});
    if (_running &&
        {
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.detached
        }.contains(state)) {
      _interrupted = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _record(state);
  Future<void> waitForResumed() async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    DateTime? resumedSince;
    while (DateTime.now().isBefore(deadline)) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        resumedSince ??= DateTime.now();
        if (DateTime.now().difference(resumedSince) >=
            const Duration(seconds: 1)) {
          return;
        }
      } else {
        resumedSince = null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
        'Real app lifecycle did not remain resumed for 1 second within 60 seconds');
  }

  Future<void> beginWhenResumed() async {
    await waitForResumed();
    _running = true;
  }

  void assertUninterrupted() {
    if (_interrupted) {
      throw StateError('Real app backgrounded during the test; incomplete run');
    }
  }

  Map<String, Object?> get snapshot => {
        'events': events,
        'interrupted': _interrupted,
        'state': WidgetsBinding.instance.lifecycleState?.name
      };
  void dispose() => WidgetsBinding.instance.removeObserver(this);
}
