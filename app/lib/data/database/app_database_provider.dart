import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// Provides the singleton [AppDatabase] and closes it when the provider is
/// disposed.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});
