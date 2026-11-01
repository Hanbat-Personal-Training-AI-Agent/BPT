import '../../auth/providers/auth_provider.dart';

/// In-memory capture provenance, carried through navigation without serializing
/// credentials or assigning an unowned photo folder to a newly logged-in user.
class CalibrationCapture {
  const CalibrationCapture({required this.sessionPath, required this.session});
  final String? sessionPath;
  final AuthSessionLease? session;
}
