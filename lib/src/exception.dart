/// Exception thrown when Mosh parsing, framing, or cryptography fails.
class MoshException implements Exception {
  /// Creates a Mosh exception with a human-readable [message].
  const MoshException(this.message, [this.cause]);

  /// Human-readable error message.
  final String message;

  /// Optional underlying error or rejected input.
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    return cause == null
        ? 'MoshException: $message'
        : 'MoshException: $message ($cause)';
  }
}
