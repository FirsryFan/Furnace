import 'package:flutter/services.dart' show rootBundle;

import '../domain/design_board.dart';

/// Where the board's read-only data comes from.
///
/// A tiny interface so widget tests can inject a fixture without depending on
/// the Flutter asset bundle (which is also why the production implementation is
/// the only place that touches [rootBundle]).
abstract class DesignBoardSource {
  Future<DesignBoardData> load();
}

/// Loads the trimmed local JSON asset bundled with the app.
///
/// The asset is generated from the workspace reference library and copied into
/// `assets/design_board.json`; it is static, so no cache/refresh logic exists.
class AssetDesignBoardSource implements DesignBoardSource {
  const AssetDesignBoardSource({this.assetPath = defaultAssetPath});

  static const String defaultAssetPath = 'assets/design_board.json';

  final String assetPath;

  @override
  Future<DesignBoardData> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return DesignBoardData.decode(raw);
  }
}
