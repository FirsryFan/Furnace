// The version constant is maintained by hand, so it is the kind of fact that
// silently rots. Two callers depend on it - Settings -> About and the
// `fetch_page` User-Agent - and both would keep "working" while lying, so the
// constant is compared against the one file that really defines the build.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/app_info.dart';

void main() {
  test('the advertised version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true)
        .firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml has no version: line');
    expect(
      match!.group(1),
      '$kAppVersion+$kAppBuildNumber',
      reason: 'bump lib/core/app_info.dart with pubspec.yaml',
    );
  });

  test('the User-Agent names the app and its version', () {
    expect(kAppUserAgent, 'Furnace/$kAppVersion (+local assistant)');
  });
}
