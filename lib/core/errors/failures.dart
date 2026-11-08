sealed class Failure implements Exception {
  final String message;
  const Failure(this.message);
  @override
  String toString() => message;
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class PrinterFailure extends Failure {
  const PrinterFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

class BackupFailure extends Failure {
  const BackupFailure(super.message);
}
