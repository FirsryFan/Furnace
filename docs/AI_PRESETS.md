# Agent / subagent presets and the direct student path

Date: 2026-11-14
Status: bottom layer only; no preset-selection UI yet.

## DSH semantics this mirrors

These are the rules the Furnace implementation follows (they are DSH's, not
invented here):

1. A preset is selected only on a **blank** session - one with no messages and
   no run yet.
2. The session records the preset **id**. Once the session stops being blank,
   selecting again is rejected; the running agent keeps the composition it
   started with.
3. A subagent receives its preset when the subagent session is created; the
   subagent session records it and it is immutable from then on.
4. There is **no persisted preset version, hash, or definition snapshot**.
   Restoring a session after a restart resolves the current definition with the
   same id; old revisions are not retained.
5. A preset is a **composition** (tools + prompt + persona), not a database row.
   Furnace stores only the id string.

## Furnace model

| Concern | Where |
|---|---|
| Preset ids + resolution | `app/lib/features/ai/domain/agent_preset.dart` (`AgentPreset`, `SubagentPreset`, `ConversationPresetState`) |
| Persistence + blank-session rule | `ai_conversations.agent_preset_id` / `subagent_preset_id`; `AiRepository.createConversation`, `setConversationPresets`, `presetStateFor` |
| Schema change | v43 -> v44 (`AppDatabase.schemaVersion == 44`), two nullable columns, no backfill |
| Routing | `app/lib/features/ai/application/conversation_runner.dart` (`ConversationRunner`) |
| Student path itself | `StudentModeController` -> `StudentSolver` (isolated, no `AgentLoop`, no tool registry) |
| Provider wiring | `studentModeControllerProvider`, `conversationRunnerProvider` in `ai_providers.dart` |

Stored ids:

- `AgentPreset.assistant` = `'assistant'` (the normal agent loop).
- `AgentPreset.studentSolver` = `'student_solver'` (direct student mode).
- `SubagentPreset.inherit` = `'inherit'` (resolution for a NULL column).
- `SubagentPreset.studentSolver` = `'student_solver'`.

NULL/unknown ids resolve to `assistant` / `inherit`, so an upgraded database
keeps its previous behaviour exactly.

## Blank session = immutable preset

`ConversationPresetState.locked` is **derived**, not stored: it is true as soon
as the session has any message (a run always writes one). This is why there is
no `locked_at`, `preset_version` or `preset_hash` column: they would be invented
state that DSH does not have, and they would freeze a definition that is meant
to be resolved live by id.

`AiRepository.setConversationPresets` throws
`ConversationPresetsLockedException` once the session has started. The exception
is a wiring error, not a user action: nothing in the UI is allowed to change a
preset after the first message.

`AgentLoop.sendUserMessage` additionally refuses a conversation whose preset is
not `assistant`, with an error on the turn state. This is defence in depth: even
if a future caller wires the chat page straight to the loop, a student-preset
session still cannot be answered by the main agent.

## Direct student mode

`ConversationRunner.startStudentSession` is the top-level entry:

```dart
final runner = ref.read(conversationRunnerProvider(/* loop id */));
final result = await runner.startStudentSession(
  question: '题干文字（可空，题图优先）',
  images: pendingImages,
);
// result.studentOutcome!.answerSheet -> choice / result / process
```

It creates a conversation with `AgentPreset.studentSolver` **while blank**, then:

1. converts the attached pictures to `ChatImagePart`s (the solver receives the
   picture itself; the user never describes it);
2. persists the user message (this is what makes the session non-blank and
   therefore what locks the preset);
3. calls `StudentSolver` directly through `StudentModeController` - the main
   `AgentLoop` is never constructed for this session;
4. persists the assistant message as the **answer sheet** text (see below).

`ConversationRunner.sendUserMessage` routes an existing session by its recorded
preset: `assistant` delegates to an injected `StandardAgentRunner` (a thin
adapter over `AgentLoop`), `student_solver` takes the direct path above.

## Answer sheet

The solver output is structured, not free text. The prompt requires:

```
【题型】选择题 / 填空题 / 解答题
【答案】最终结果（选择题先写选项字母；填空题只写结果；解答题写最终结论）
【过程】只有解答题写必要的解题步骤（不是完整思维链，不是 meta 解释）
```

`StudentAnswerSheet.parse` turns that into:

- `kind`: `choice` / `fillIn` / `solution`;
- `choice`: option letters for a choice question (`B`, `AC`), otherwise null;
- `result`: the final result on the answer sheet;
- `process`: the necessary working (solution questions only);
- `structured`: whether the model actually emitted the markers;
- `raw`: the whole model text, kept for the trace.

A model that ignores the markers still gets wrapped: `structured == false`, the
full text becomes `result`, and the kind falls back to `solution`. Nothing is
dropped and nothing is guessed into a wrong kind.

The same structure appears in `StudentSolverResult.answerSheet`,
`StudentSolverResult.toModelJson()['answer_sheet']`, the trace JSON
(`answer_sheet` field), and the compatibility tool's model result.

## Compatibility

`solve_question_as_student` remains registered as a main-agent tool for the case
where the user explicitly asks the assistant to delegate. It is **not** the
student-mode default path: that is the preset/session route above.

## Limits

- No preset-selection UI yet: creating a conversation with a preset, and
  changing it while blank, are application-layer APIs.
- Subagent spawning does not exist in Furnace yet; `subagent_preset_id` records
  the composition a future subagent session would be created with.
- Traces are local JSON files under `<appSupport>/student_solver_traces/`; there
  is no trace browser.
- The 20k reasoning / 3k answer budgets are constants in
  `studentSolverProvider`, not user settings.
