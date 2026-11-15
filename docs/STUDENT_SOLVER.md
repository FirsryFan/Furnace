# Student solver integration

Date: 2026-11-14
Status: direct student mode is a top-level **session preset** (not a tool); no
preset-selection UI yet. See `docs/AI_PRESETS.md` for the preset semantics.

## What it is

A student-mode solve of one question, run through the same `ModelAdapter` the
rest of Furnace uses:

- one bounded reasoning turn (20,000 output tokens in the provider);
- if reasoning exhausts the budget or produces no answer, one answer-reserve
  turn (3,000 tokens) that receives the partial draft;
- one natural reading, one answer set;
- no access to the question's stored answer/solution;
- no database writes.

This is the Flutter counterpart of `solver-lab/agent-core` (Python). The Python
component is the reference implementation used for experiments; the Flutter
code is the product integration.

## Files

| File | Role |
|---|---|
| `app/lib/features/ai/domain/student_solver.dart` | pure domain solver + result + answer-sheet contract; no Flutter imports |
| `app/lib/features/ai/domain/student_answer_sheet.dart` | typed answer sheet (`choice` / `fillIn` / `solution`) parsed from the marked output |
| `app/lib/features/ai/domain/agent_preset.dart` | `AgentPreset` / `SubagentPreset` ids and resolution (DSH semantics) |
| `app/lib/features/ai/application/conversation_runner.dart` | routes a message by the session's preset; starts top-level student sessions |
| `app/lib/features/ai/application/student_mode_controller.dart` | direct solve path: solver + current images + trace store, no agent loop |
| `app/lib/features/ai/tools/student_solver_tool.dart` | `solve_question_as_student` compatibility tool (not the default path) |
| `app/lib/features/ai/infrastructure/student_trace_store.dart` | local trace JSON under `<appSupport>/student_solver_traces/` |
| `app/lib/features/ai/domain/student_solver_context.dart` | current user-turn image context shared from the loop to the tool |
| `app/lib/features/ai/application/ai_providers.dart` | `studentSolverProvider`, `studentModeControllerProvider`, `conversationRunnerProvider` |
| `app/lib/features/ai/domain/tool_registry.dart` | registers the compatibility tool only when a usable model exists |
| `app/test/features/ai/student_answer_sheet_test.dart` | answer-sheet parsing + serialization |
| `app/test/features/ai/conversation_presets_test.dart` | preset create/read/blank-session lock/legacy fallback |
| `app/test/features/ai/conversation_runner_test.dart` | student preset never calls the main agent; answer sheet stored |
| `app/test/features/ai/v44_migration_test.dart` | v43 -> v44 preset columns + self-heal |
| `app/test/features/ai/student_mode_controller_test.dart` | direct solve, images, trace, no agent-loop dependency |
| `app/test/features/ai/student_solver_test.dart` | first answer, length fallback, failure |
| `app/test/features/ai/student_solver_tool_test.dart` | compatibility tool result and argument validation |
| `app/test/features/ai/student_solver_registration_test.dart` | tool absent without model; present with model |
| `app/tool/student_solver_smoke.dart` | real-API smoke through the Flutter code path |

## Direct student mode (the default path)

Student mode is a **top-level session preset**, not a tool of the main agent.
`ConversationRunner.startStudentSession` creates a conversation whose
`agent_preset_id` is `student_solver` while it is blank, then:

1. passes the attached pictures straight to the solver;
2. persists the user message (the session is no longer blank, so its preset is
   locked from here on);
3. calls `StudentModeController` -> `StudentSolver` directly - the main
   `AgentLoop` is never constructed for this session and never sees the
   question or the answer;
4. persists the assistant message as the answer sheet.

`ConversationRunner.sendUserMessage` routes an existing session by its recorded
preset, so a `student_solver` conversation never falls back to the main agent.
`AgentLoop.sendUserMessage` also refuses a non-assistant preset, as defence in
depth.

## Answer sheet (structured output)

The solver no longer returns free text. The prompt requires three marked
sections and `StudentAnswerSheet.parse` turns them into typed fields:

```text
【题型】选择题 / 填空题 / 解答题
【答案】最终结果（选择题先写选项字母；填空题只写结果；解答题写最终结论）
【过程】只有解答题写必要的解题步骤（不是完整思维链，不是 meta 解释）
```

- `choice`: option letters (`B`, `AC`) for a choice question, else null;
- `result`: the final result on the answer sheet;
- `process`: necessary working for a solution question;
- `structured`: whether the model actually used the markers;
- `raw`: the complete model text, kept for the trace.

A model that ignores the markers is still wrapped (`structured == false`, the
text becomes `result`, kind falls back to `solution`) instead of leaking a bare
string through the API. The structure appears in
`StudentSolverResult.answerSheet`, `toModelJson()['answer_sheet']`, the trace's
`answer_sheet` field, and the compatibility tool's model result.

## Tool contract (compatibility only)

Name: `solve_question_as_student`

Arguments:

- `question_id`: optional question-library id. When present, the tool reads the
  stem and the stem images (`QuestionMediaStore`, `role='stem'`) from Furnace.
- `question`: complete question text. Must not include answer/solution.
- When `question` is used, the tool automatically attaches the images of the
  **current user turn** (`StudentSolverContext`, filled by `AgentLoop`); when
  `question_id` is used, it reads the stored stem images instead.
- Exactly one of the two is required.

Returns:

- user-facing summary (one line);
- model-visible JSON: `ok`, `answer`, `answer_sheet` (kind / choice / result /
  process / structured), token counts, `finish_reason`, `attempts`,
  `reasoning_chars`, and `trace_path`; the raw reasoning is intentionally not
  returned to the conversation.

Read-only: yes. No writes, no approval prompt. This tool exists only for the
case where the user explicitly asks the main assistant to delegate; it is not
the student-mode default path (see above).

## Verification (preset + answer-sheet layer, 2026-11-14)

Code generation (schema v44):

```text
dart run build_runner build --delete-conflicting-outputs
Built with build_runner/aot in 92s; wrote 1031 outputs.
```

Analyzer (only pre-existing issues in files this round did not touch):

```text
dart analyze lib/features/ai
2 issues found: unused_local_variable + unused_element in
presentation/ai_chat_page.dart (unchanged file)

dart analyze lib/data/repositories/ai_repository.dart \
  lib/data/database/tables.dart lib/data/database/database.dart
1 issue found: use_super_parameters in database.dart:96 (pre-existing)

dart analyze test/features/ai/student_answer_sheet_test.dart \
  test/features/ai/conversation_presets_test.dart \
  test/features/ai/conversation_runner_test.dart \
  test/features/ai/v44_migration_test.dart \
  test/features/ai/student_mode_controller_test.dart \
  test/features/ai/student_solver_test.dart \
  test/features/ai/student_solver_tool_test.dart \
  test/features/ai/student_solver_registration_test.dart
No issues found!
```

Tests:

```text
flutter test test/features/ai/student_answer_sheet_test.dart \
  test/features/ai/conversation_presets_test.dart \
  test/features/ai/conversation_runner_test.dart \
  test/features/ai/v44_migration_test.dart \
  test/features/ai/student_mode_controller_test.dart
All tests passed (36 tests across the five files).

flutter test test/features/ai
All tests passed (747 tests).
```

Windows debug build:

```text
flutter build windows --debug
Building Windows application...  20.3s
√ Built build\windows\x64\runner\Debug\furnace.exe
```

## Verification

Targeted analyzer:

```text
dart analyze lib/features/ai/domain/student_solver.dart \
  lib/features/ai/tools/student_solver_tool.dart \
  lib/features/ai/domain/tool_registry.dart \
  lib/features/ai/application/ai_providers.dart
No issues found!
```

Targeted tests:

```text
flutter test test/features/ai/student_solver_test.dart \
  test/features/ai/student_solver_tool_test.dart \
  test/features/ai/student_solver_registration_test.dart
All tests passed (11 tests). Existing AI feature suite: 747 tests pass.

Windows debug build:

```text
flutter build windows --debug
Building Windows application... 57.9s   (first build)
Building Windows application... 14.6s   (incremental after preset work)
√ Built build\windows\x64\runner\Debug\furnace.exe
```
```

Existing registry test still passes: `all 29 built-in tools` with no solver
configured, because the new tool is conditional.

Real Flutter audit runs (actual DeepSeek API, **original** Q15 text + figure,
**no answer-guiding instruction**):

```text
run 1: elapsed 141.6s, attempts 2, completion 20,643, reasoning 28,090
       answer: both mass branches, 17/2 < E < 12   (extra branch)
run 2: elapsed 147.2s, attempts 2, completion 20,439, reasoning 28,335
       answer: m2/m1 ≤ 1, E ≥ 17/2                 (wrong)
```

Teacher-confirmed answer (2026-11-14, corrected):

- (1) \(g\sin\theta\)
- (2) \(m_2/m_1\le1\) **or** \(m_2/m_1=7\)
- (3) \(17/2\,m_1gR\sin\theta \le E_{k0}\le 12\,m_1gR\sin\theta\)

DSH's run got (3)=12 and only \(m_2/m_1=7\) in (2); the teacher confirmed the
track branch \(m_2/m_1\le1\) is also valid.

The later no-hint `StudentRun` v3 run produced exactly this correct content:

```text
elapsed 273.3s, completion 20,709, reasoning 28,334
answer: (2) m2/m1≤1 or 7; (3) 17/2 ≤ E ≤ 12
```

It was nevertheless marked `finalized_unverified`: the verifier used the same
20k reasoning adapter, hit `finish_reason=length`, emitted 0 text and no JSON,
so the run could not certify it. That is a verifier budget/protocol bug, not an
answer-content failure.

## v2 architecture (2026-11-14)

The `student_solver` preset now runs `StudentRun` (not just one
`StudentSolver.solve` call):

```text
solve -> answer reserve -> process audit -> content verify -> repair (<=1) -> finalize
```

- `agent_runs` / `agent_steps` / `agent_verifications` / `agent_claims` /
  `agent_experiences` are persisted in schema v45.
- `ProcessAuditor` reads the raw reasoning and flags loops, self-doubt and
  no-progress; a process blocker prevents a `finalized` pass.
- `StudentVerifier` re-solves only to find differences; it re-examines each
  difference and does not treat its own answer as standard. It never receives
  the solver's raw CoT. `AnswerOracle` allows a governed rubric to produce a
  deterministic verdict without a model call; the standard answer never enters
  the solver prompt.
- The exam persona is a **behavior/knowledge-scope constraint**, not a
  capability cap: it forbids university-level methods, calculators and external
  tools, but explicitly says reasoning ability is not limited and the model must
  not “play dumb” by omitting necessary derivations.
- Claims extracted by `StudentProcessAuditor` go to `ClaimLedger`; only verified
  runs write an `agent_experiences` row.

Current evidence (2026-11-14):

- 941 AI tests pass; Windows debug build succeeds.
- A real no-hint Q15 run (2026-11-14 19:28) produced the teacher-confirmed
  content: (2) \(m_2/m_1\le1\) or \(7\); (3) \(17/2\le E\le12\).
- A later v4 run switched the verifier to the 3k answer adapter. The verifier
  returned `fail/wrong_branch`, but its own independent answer was wrong
  (`E≥25/2` / `E≥17/2`), and repair removed the correct `E≤12` upper bound.
  So the current verifier's independent re-solve is not reliable enough to
  authorize repair; v3's answer should be kept.

## Limits / next wiring

- The trace is a JSON file under `<appSupport>/student_solver_traces/`, not a
  database row; there is no in-app trace browser yet.
- A `question_id` call reads stored stem images; a chat-attached image for a
  text `question` is passed through `StudentSolverContext` (the loop fills it
  from the current user message). The direct preset path passes the attached
  pictures to the solver itself.
- No preset-selection UI yet: `AiRepository.createConversation` /
  `setConversationPresets` and `ConversationRunner.startStudentSession` are the
  application-layer APIs a UI would call. See `docs/AI_PRESETS.md`.
- Subagent spawning does not exist in Furnace yet; `subagent_preset_id` records
  the composition a future subagent session is created with.
- The 20k/3k budgets are constants chosen from experiments; they are not yet
  user settings.
- This solver is the only non-assistant preset today; a preset registry with
  more compositions is future work.
