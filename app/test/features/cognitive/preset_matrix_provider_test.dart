import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/cognitive/application/preset_matrix_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asset seed loads: 19 measured + global preset bands', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seed = await container.read(presetMatrixSeedProvider.future);
    expect(seed.measuredCount, 19);
    expect(seed.hasGlobalPreset, isTrue);
    expect(seed.presetMeanFor('S'), isNotNull);
    expect(seed.missingMeasuredIds, isEmpty);
    for (final id in seed.measuredByKnowledgePoint.keys) {
      expect(seed.measuredFor(id)!.isMeasured, isTrue);
    }
  });
}
