# Agent Note: A subagent settlement notice carries the cause of the failure

Status: implemented

English | [中文](2026-09-21-subagent-settlement-carries-its-cause.zh.md)

## Problem

A parent agent learned that its background subagent had failed but never why. The two sentences it received were:

```
Background subagent <id> failed before it finished.
It left no closing message.
```

`settlementSummary` switched on `stopReason` alone, and its `'error'` arm returned a fixed sentence. The cause was available at the one place that could have carried it — `ActivationObserver.terminal(failure)` receives the thrown value — and was discarded there: `lifecycle.ts` built `{ stopReason: 'error' }` and dropped the `failure` argument.

The consequence is worse than a missing diagnostic. Every failure of every class produced byte-identical text, so a parent could not distinguish a rejected credential from a torn-down scope from a policy denial, could not judge whether retrying was safe, and could not report anything actionable. This deployment was in exactly that position: four background subagents died instantly and nothing in the session log, chat notice, or journal said why.

## Decision

The terminal lifecycle edge carries the cause, and the settlement notice renders it.

`ActivationTerminal` gains `readonly failure?: string`, the rendered cause of a teardown or durability failure, present only when one occurred. `lifecycle.ts` populates it where it observes the failure, through a local `describeFailure(failure)` returning `failure.message` for an `Error` and `String(failure)` otherwise — a rejected promise may carry any value, so the non-`Error` case is real rather than defensive.

`settlementSummary` takes the terminal instead of the bare `stopReason`, and its `'error'` arm appends ` Cause: <failure>` when a cause is present; `notifySettlement` passes the terminal through. With no cause available the sentence `failed before it finished.` is unchanged, so a backend reporting an error without one still reads as before. `out-of-process.ts` continues to flatten to `{ stopReason: 'error' }` with no cause, which is the path that exercises that arm.

The `'error'` arm still withholds the terminal's output: an answer the harness could not durably release is not a result, and surfacing it would be a correctness bug rather than a diagnostics improvement.

## Consequences

A parent can now read what went wrong and decide what to do about it. The failure text is model-visible and reaches the session log through the notice, so a cause is reconstructable from the log like any other model-visible input.

The cause arrives as one line of rendered text, not a failure class. A parent can act on it by reading it; no code path can classify or retry on it. Retry classification (provider auth, rate limit, overload, context length, network) belongs to the model-provider layer and is not addressed here.

Only the parent session's notice carries the cause. An operator reading `journalctl` still sees nothing about a child's failure, so host-level structural logging of child terminal causes remains an open gap.

## Alternatives considered

- **Log the cause at the host level instead of the notice.** Rejected as the primary fix: the parent agent is the consumer that must act on the failure, and a journal line it never reads does not let it act. Host-level logging is complementary and remains open.
- **Distinguish "never started" from "started then failed" through a `neverStarted` flag.** Implemented and then removed. The flag was populated from whether `capture()` had run before teardown, a state no test reaches through the public lifecycle without a fault-injection seam added purely to satisfy coverage; the per-file 100% coverage gate would have forced either an unreachable branch or a test-only hook. The cause, which is what makes either case actionable, is delivered without it.
- **Carry the raw thrown value rather than a string.** Rejected: the terminal crosses to the parent through a settlement notice that is model-visible text, so the value is rendered at the boundary that knows it is a diagnostic rather than carried as an opaque object to a consumer that would have to render it anyway.

## Testing

`packages/subagent/subagent/tests/continuation.spec.ts` asserts that a teardown failure's cause reaches the parent's settlement notice, for an `Error` (`scope unwind failed`) and for a non-`Error` rejection (`quota exhausted`). The withholding behaviour is asserted unchanged: the child's output stays suppressed on a failed teardown and `It left no closing message.` is still appended.

`pnpm exec tsc -p packages/subagent/subagent/tsconfig.json --noEmit` is clean and `continuation.spec.ts` is green (104 tests).
