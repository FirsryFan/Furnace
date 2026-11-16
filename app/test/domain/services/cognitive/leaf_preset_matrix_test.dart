import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/leaf_preset_matrix.dart';

void main() {
  test('parses a skeleton and does not claim measured', () {
    final seed = LeafPresetMatrixSeed.fromJson(<String, Object?>{
      'counts': <String, Object?>{'nodes': 110, 'cells': 5500},
      'presets': <String, Object?>{'S': 0.9, 'A': 0.75, 'B': 0.6, 'C': 0.4, 'D': 0.25},
      'ability_codes': <Object?>['A1', 'A2'],
      'source': 'leaf-preset-matrix.json',
      'notes': <Object?>[
        'all cells are global preset prior; not measured',
        'n_obs=0 for all',
      ],
    });
    expect(seed.nodeCount, 110);
    expect(seed.cellCount, 5500);
    expect(seed.bands, <String>['S', 'A', 'B', 'C', 'D']);
    expect(seed.abilityCodes, <String>['A1', 'A2']);
    expect(seed.isSkeleton, isTrue);
    expect(seed.allPresetGlobal, isTrue);
  });
}
