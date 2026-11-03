/// Connection to the Nox core (Go engine).
/// Desktop: the `noxd` service over loopback JSON-RPC (see go/ipc). Android (M2): a gomobile
/// AAR behind a MethodChannel with the same method names. Web/tests: [MockApi].
abstract class NoxApi {
  /// Calls an engine method (same names as engine.App: GetState, Import, Connect, ...).
  Future<dynamic> call(String method, [List<dynamic> args = const []]);

  /// Human-readable transport description for the about line.
  String get transport;
}

class NoxError implements Exception {
  final String message;
  NoxError(this.message);
  @override
  String toString() => message;
}
