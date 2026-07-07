import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/services/nostr_service.dart';

/// Connection state of each configured relay. Invalidate to refresh.
final relayStatusProvider = FutureProvider.autoDispose<List<RelayStatus>>(
  (ref) => ref.watch(nostrServiceProvider).relayStatuses(),
);
