/// Failure hierarchy shared by all layers. Every repository / service
/// method either succeeds or throws one of these (async: completes with
/// error). UI maps them to localized messages.
sealed class Failure implements Exception {
  final String message;
  final Object? cause;
  const Failure(this.message, [this.cause]);

  @override
  String toString() => '$runtimeType: $message';
}

class StorageFailure extends Failure {
  const StorageFailure(super.message, [super.cause]);
}

class BleFailure extends Failure {
  const BleFailure(super.message, [super.cause]);
}

class BlePermissionFailure extends BleFailure {
  const BlePermissionFailure(super.message, [super.cause]);
}

class HealthFailure extends Failure {
  const HealthFailure(super.message, [super.cause]);
}

class HealthPermissionFailure extends HealthFailure {
  const HealthPermissionFailure(super.message, [super.cause]);
}

class NostrFailure extends Failure {
  const NostrFailure(super.message, [super.cause]);
}

class RelayFailure extends NostrFailure {
  const RelayFailure(super.message, [super.cause]);
}

class TorFailure extends NostrFailure {
  const TorFailure(super.message, [super.cause]);
}

class SignerFailure extends Failure {
  const SignerFailure(super.message, [super.cause]);
}

/// Amber not installed / user rejected the signing request.
class SignerUnavailableFailure extends SignerFailure {
  const SignerUnavailableFailure(super.message, [super.cause]);
}

class SignerRejectedFailure extends SignerFailure {
  const SignerRejectedFailure(super.message, [super.cause]);
}

class ExportFailure extends Failure {
  const ExportFailure(super.message, [super.cause]);
}
