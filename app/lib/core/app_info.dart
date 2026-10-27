/// Identity facts about this build, in one place.
///
/// The version shown in Settings -> About and the version sent in the
/// `fetch_page` User-Agent are the same fact, so they read the same constant
/// instead of two hand-edited strings that drift apart. Nothing here is
/// discovered at runtime: a wrong constant is caught by
/// `test/core/app_info_test.dart`, which compares it against `pubspec.yaml`.
library;

/// Marketing version, matching `pubspec.yaml`'s `version:` before the `+`.
const String kAppVersion = '0.6.12';

/// Build number, matching `pubspec.yaml`'s `version:` after the `+`. Android
/// publishes this as `versionCode`.
const int kAppBuildNumber = 31;

/// What the app calls itself over HTTP. Kept honest about who is calling rather
/// than impersonating a browser.
const String kAppUserAgent = 'Furnace/$kAppVersion (+local assistant)';
