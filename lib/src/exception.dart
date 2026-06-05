class MoshException implements Exception {
  const MoshException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    return cause == null
        ? 'MoshException: $message'
        : 'MoshException: $message ($cause)';
  }
}
