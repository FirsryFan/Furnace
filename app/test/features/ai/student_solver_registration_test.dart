import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/student_solver.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/tools/student_solver_tool.dart';

void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late TimeBlockRepository blocks;
  late AnkiRepository anki;
  late TagRepository tags;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    blocks = TimeBlockRepository(db);
    anki = AnkiRepository(db);
    tags = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('the student solver tool is absent without a configured adapter', () {
    final registry = ToolRegistry.forApp(
      db: db,
      tasks: tasks,
      blocks: blocks,
      anki: anki,
      tags: tags,
    );
    expect(registry.byName(SolveQuestionAsStudentTool.toolName), isNull);
  });

  test('the student solver tool is registered when an adapter exists', () {
    final solver = StudentSolver(
      reasonAdapter: FakeModelAdapter([
        [const ModelTextDelta('answer')],
      ]),
    );
    final registry = ToolRegistry.forApp(
      db: db,
      tasks: tasks,
      blocks: blocks,
      anki: anki,
      tags: tags,
      studentSolver: solver,
    );
    expect(registry.byName(SolveQuestionAsStudentTool.toolName), isNotNull);
  });
}
