// The turn/usage figures themselves.
//
// These are the numbers the panel puts on screen, so the tests are about the
// arithmetic and about the one thing that is easy to get wrong: a figure the
// provider did not report must stay `null` (a dash) rather than becoming a
// confident zero, and the rate must be divided by generation time rather than
// by how long the whole turn happened to take.
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';

void main() {
  group('a turn nothing was measured for', () {
    const empty = TurnUsage();

    test('reports dashes, not zeros', () {
      expect(empty.isEmpty, isTrue);
      expect(empty.hasUsage, isFalse);
      expect(empty.totalTokens, 0);
      // The three figures that would be a lie as `0` or `0%`.
      expect(empty.cacheHitRatio, isNull);
      expect(empty.tokensPerSecond, isNull);
      expect(empty.contextUsageRatio, isNull);
      expect(empty.liveTokensPerSecond, isNull);
    });
  });

  group('rounds, steps and tokens', () {
    const twoRounds = TurnUsage(
      rounds: 2,
      maxRounds: 8,
      roundsWithUsage: 2,
      promptTokens: 2200,
      completionTokens: 100,
      cacheHitPromptTokens: 1900,
      cacheMissPromptTokens: 300,
      generationTime: Duration(seconds: 3),
      lastPromptTokens: 1200,
      toolCallsExecuted: 1,
      contextWindowTokens: 65536,
    );

    test('total tokens are prompt plus completion over the turn', () {
      expect(twoRounds.totalTokens, 2300);
      expect(twoRounds.hasUsage, isTrue);
      expect(twoRounds.isEmpty, isFalse);
    });

    test('the rate divides by generation time only', () {
      // 100 completion tokens over a 3 s generation window. Deliberately not
      // "over the turn's wall time": the turn also waited for a tool, and that
      // wait is not the model's speed.
      expect(twoRounds.tokensPerSecond, closeTo(100 / 3, 1e-9));
    });

    test('context occupancy is the last prompt over the configured window', () {
      expect(twoRounds.contextUsageRatio, closeTo(1200 / 65536, 1e-12));
    });
  });

  group('cache hit rate', () {
    test('is hits over hits plus misses', () {
      const usage = TurnUsage(
        roundsWithUsage: 2,
        promptTokens: 1000,
        cacheHitPromptTokens: 750,
        cacheMissPromptTokens: 250,
      );
      expect(usage.cacheHitRatio, closeTo(0.75, 1e-12));
      expect(usage.cacheAccountingIsPartial, isFalse);
    });

    test('is a real 0% when the provider really reported no hits', () {
      const usage = TurnUsage(
        roundsWithUsage: 1,
        promptTokens: 500,
        cacheHitPromptTokens: 0,
        cacheMissPromptTokens: 500,
      );
      expect(usage.cacheHitRatio, 0.0);
      // 0.0 and null are different answers: this one is a measurement.
      expect(usage.cacheHitRatio, isNotNull);
    });

    test('is null - not 0% - when the endpoint reports nothing', () {
      const usage = TurnUsage(roundsWithUsage: 1, promptTokens: 500);
      expect(usage.cacheHitRatio, isNull);
      expect(usage.cacheAccountingIsPartial, isFalse);
    });

    test('is null for the meaningless all-zero pair', () {
      // Some gateways send `0/0` for every request. A prompt cannot be empty,
      // so that is an absent measurement wearing the shape of a real one.
      const usage = TurnUsage(
        roundsWithUsage: 1,
        promptTokens: 500,
        cacheHitPromptTokens: 0,
        cacheMissPromptTokens: 0,
      );
      expect(usage.cacheHitRatio, isNull);
    });

    test('says so when only some rounds reported the pair', () {
      const usage = TurnUsage(
        rounds: 2,
        roundsWithUsage: 2,
        promptTokens: 1000,
        cacheHitPromptTokens: 200,
        cacheMissPromptTokens: 300,
      );
      expect(usage.cacheHitRatio, closeTo(0.4, 1e-12));
      expect(usage.cacheAccountingIsPartial, isTrue,
          reason: 'the ratio describes 500 of the 1000 prompt tokens');
    });
  });

  group('the live rate while a round is still streaming', () {
    test('is null before the first character arrives', () {
      const usage = TurnUsage(inFlightElapsed: Duration(milliseconds: 800));
      expect(usage.liveTokensPerSecond, isNull,
          reason: 'there is nothing in the numerator yet');
    });

    test('estimates the in-flight round from the characters that arrived', () {
      const usage = TurnUsage(
        completionTokens: 100,
        generationTime: Duration(seconds: 2),
        // 25 characters at 2.5 characters per token = 10 estimated tokens.
        inFlightChars: 25,
        inFlightElapsed: Duration(seconds: 1),
      );
      // (100 + 10) tokens over (2 s + 1 s).
      expect(usage.liveTokensPerSecond, closeTo(110 / 3, 1e-9));
    });

    test('uses the same time definition as the frozen figure', () {
      const usage = TurnUsage(
        completionTokens: 50,
        generationTime: Duration(seconds: 2),
        inFlightChars: 0,
        inFlightElapsed: Duration.zero,
      );
      // With nothing in flight, live and frozen agree: same numerator source,
      // same denominator, same definition.
      expect(usage.liveTokensPerSecond, closeTo(usage.tokensPerSecond!, 1e-9));
      expect(usage.tokensPerSecond, closeTo(25, 1e-9));
    });
  });

  group('AgentTurnState', () {
    test('keeps rounds and usage.rounds from disagreeing', () {
      const state = AgentTurnState();
      final updated = state.copyWith(
        rounds: 3,
        usage: const TurnUsage(promptTokens: 10, roundsWithUsage: 1),
      );
      expect(updated.rounds, 3);
      expect(updated.usage.rounds, 3,
          reason: 'one accumulator feeds both, so a caller cannot desync them');
      expect(updated.usage.promptTokens, 10);
    });

    test('defaults keep existing constructor calls working', () {
      const state = AgentTurnState(generating: true);
      expect(state.usage.isEmpty, isTrue);
      expect(state.usage.maxRounds, AgentLoop.defaultMaxRounds);
      expect(state.usage.contextWindowTokens, AgentLoop.defaultContextWindowTokens);
    });
  });
}
