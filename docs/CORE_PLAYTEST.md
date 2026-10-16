# Core-loop demo 0.3.0-core-playtest.1

## Product scope

The public demo tests whether a player can read danger, author a plan, understand
the simultaneous result, and choose to play again. It keeps the eight-second
planning limit and 0.75-second execution. It adds no fighter, attack or arena.

- Start Duel: two Duelists, first to three hits, against the opponent ladder.
  Five named CPUs play in order (The Apprentice, The Hound, The Warden, The
  Spire, The Phantom); each has its own skill preset and a style the planner
  reads: closing in and throwing early, keeping the knife until a throw is sure,
  taking the high ground with full draws, throwing through the wrap seam. Each
  is fought in its own arena, in rotation order: Crosshair Court, Clockwork
  Gallery (timed shutters), Stilled Hall (stasis fields), Pulse Chamber (pulse
  orbs), Endless Descent (four-way wrap). Beating
  the current opponent unlocks the next and saves locally.
  Side edges wrap left/right; open shafts connect bottom/top.
- Learn to Play: three real-physics timed exercises, retryable without penalty.
  Lesson 2 reveals a committed jump onto a low ledge, with a preparation pose
  and a gold landing aim cue. A roughly three-quarter charge can catch the
  landing through normal projectile physics; retries restore the same jump.
  Normal CPU plans stay hidden.
  Lesson 3 sends a low knife from the left and a second knife from the right
  across the straight-jump landing. Both are visible from the start and retain
  their identity and momentum across two windows. Jumping then steering left
  escapes; jumping then coasting straight down is caught by the second knife.
- Readable embedded font for instructions, timeline and feedback, consistent on
  desktop and Web. Atkinson Hyperlegible is redistributed with its OFL license.
- Visible Lock Plan, player identity, controls and last-turn review. UI clicks
  do not aim or charge an attack. Review supports mouse playback/stepping/return.
- Rematches retain the arena, rules and opponent. After a win, a separate action
  starts the next opponent; the result-screen arrows revisit any opponent
  already reached.
- Custom Match is public: any of the five arenas, 2 to 4 fighters, each CPU's
  skill preset and the match length. Experiments stay behind `--dev-tools`.
- Online remains a separate existing private-room route. Do not pool CPU and
  online findings when assessing fun or opponent readability.

## Feedback and measurement

Menu and result screens open an editable email draft for patochaos@gmail.com.
Full reports travel by clipboard, avoiding oversized mailto URLs. No automatic
mail or telemetry upload is performed.

Reports checkpoint after events, including lesson attempts/results, timeouts,
locks with planning time, actual throws, hits and abandonment. Completed or
abandoned matches append to the local session log. A rematch-start event links
back to the previous match. Sudden process/browser termination may leave the
last checkpoint marked in progress; do not infer an abandonment reason from it.

## Observed playtest protocol

Use five people unfamiliar with the project. Let each start without coaching.
Record interventions, timeouts, confusing hits and whether they voluntarily
rematch. Ask them to explain one hit and one miss, then describe their next plan.

Provisional gates for broad publication:

- Four of five complete a first valid plan without intervention.
- Four of five can explain the loop and one combat outcome.
- A majority choose another match without prompting.
- No recurring visibility problem prevents reading an immediate threat.
- Validate the distributed build on a clean device/browser and run a separate
  two-device online test before advertising online reliability.

These are intended observation gates, not measured results. Automated tests
prove behavior, not fun.

## Verification

`CoreDemoTest` exercises the public entry point, actual movement/interception/
survival outcomes, timer expiry, world persistence, direct graduation to a duel,
feedback encoding, abandoned reports, and the next-opponent flow. `OpponentLadderTest`
covers rung order, style weights reaching the planner, saved progress and the
result-screen controls. Existing menu,
readiness, controls, replay, prediction and online suites cover shared behavior.
`CoreDemoVisualTest` captures the public screens at 1280x720 and the live planner
at 1024x576. Web export is smoke-tested locally with browser input.

The local browser check confirmed timed execution into turn two, lesson retry,
feedback keyboard entry and the copy action without JavaScript errors. Native
captures confirmed readable replay controls and the smaller planner layout.
The unpacked Web export completed successfully. External email delivery,
clean-device compatibility, two-device online play and human fun remain unverified.

No ZIP or live deployment is produced by this workflow. `Play.bat` continues to
launch the current repository through Godot.
