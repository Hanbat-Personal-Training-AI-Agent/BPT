import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/providers/auth_provider.dart';

/// A family key changes on account/login lifetime, never on token refresh.
/// Keeping each lifetime in a separate async provider prevents Riverpod's previous
/// value during reload from exposing another account's aggregate.
class AggregateSessionScope {
  AggregateSessionScope(this.lease);
  final AuthSessionLease lease;
}

final aggregateSessionScopeProvider = Provider<AggregateSessionScope?>((ref) {
  ref.watch(authNotifierProvider
      .select((auth) => (owner: auth, identity: auth.sessionIdentity)));
  final lease = ref.read(authNotifierProvider).captureSession();
  return lease == null ? null : AggregateSessionScope(lease);
});
