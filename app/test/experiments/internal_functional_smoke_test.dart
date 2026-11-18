import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/features/questions/application/question_corpus_reader.dart';
import 'package:furnace/features/questions/application/question_library_reader.dart';

void main() {
  test('PowerShell internal functional probe on real DB', () async {
    final src = File(r'E:\Furnace\data\furnace.db');
    final tmp = await Directory.systemTemp.createTemp('furnace-internal');
    final copy = await src.copy('${tmp.path}/furnace.db');
    final db = AppDatabase.forTesting(NativeDatabase(copy));
    addTearDown(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });

    final library = await readQuestionLibrary(db, limit: 0);
    final groups = library.entries.where((e) => e.groupSize > 1).toList();
    // ignore: avoid_print
    print('LIB total=${library.entries.length} groups=${groups.length} '
        'groupRows=${groups.fold<int>(0, (n, e) => n + e.groupSize)}');
    expect(groups, isNotEmpty);
    expect(groups.every((g) => g.groupQuestionIds.length == g.groupSize), isTrue);

    final corpus = await readPaperCorpus(db);
    // ignore: avoid_print
    print('CORPUS candidates=${corpus.candidates.length} subjects=${corpus.subjectKeys}');
    expect(corpus.candidates, isNotEmpty);

    final plan = PaperComposer.compose(
      candidates: corpus.candidates,
      spec: const PaperSpec(targetCount: 6),
      knowledgePointNames: corpus.knowledgePointNames,
      knowledgePointTagPaths: corpus.knowledgePointTagPaths,
    );
    // ignore: avoid_print
    print('PLAN items=${plan.items.length} unique=${plan.items.map((i) => i.questionId).toSet().length}');
    expect(plan.items, hasLength(6));
    expect(plan.items.map((i) => i.questionId).toSet(), hasLength(6));

    final questions = await db.select(db.questions).get();
    final pending = questions.where((q) =>
        (q.answer?.trim().isEmpty ?? true) &&
        (q.solution?.trim().isEmpty ?? true)).length;
    // ignore: avoid_print
    print('DB questions=${questions.length} pending=$pending');
    expect(questions, hasLength(125));
    expect(pending, 60);
  });
}
