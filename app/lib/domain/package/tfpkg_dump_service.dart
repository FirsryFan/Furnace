import '../../data/package/tfpkg_codec.dart';

/// Anything that can produce a `.tfpkg` logical dump.
///
/// Declared as an interface so the package layer depends on the shape of a
/// dump rather than on the database, which keeps both sides testable in
/// isolation.
abstract interface class TfpkgDumpSource {
  /// Produces the dump to encode.
  ///
  /// [excludeSensitive] blanks stored secrets (today: the AI API key) so a
  /// package can be handed to someone else without handing over a working
  /// credential.
  Future<TfpkgDump> exportDump({
    String? appVersion,
    bool excludeSensitive = false,
  });
}
