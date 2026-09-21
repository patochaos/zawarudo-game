# Za Warudo core-loop playtest

The question for this demo: is planning a move, committing it, and watching the
clash fun enough to play again?

## First session

1. Launch `Play.bat` with Godot installed, or open the supplied playable build.
2. Choose **LEARN TO PLAY**. Read the short instruction before each attempt.
   Move into a target zone, intercept a moving opponent, then escape an earlier
   knife across two turns. Every playable turn has an eight-second limit.
   Mistakes offer a fresh attempt; completion starts your first duel.
3. **START DUEL** skips lessons and immediately starts two Duelists in Endless
   Descent: you against a Novice CPU, first to three hits. Cross a side edge to
   return on the opposite side; the open shafts connect bottom and top.
4. A/D records movement; Space jumps; mouse aims; hold/release left-click places
   a throw. R/right-click removes the throw; F resets the route. Left Shift or
   **LOCK PLAN** confirms. Your current plan executes when the timer expires.
5. After a turn, **REVIEW** lets you replay slowly and step through the outcome.
   Review pauses offline planning; return to resume the remaining clock.
6. Finish the match and choose **REMATCH**, **TRY STANDARD CPU**, or **SEND FEEDBACK**.
   Escape during play returns to the title and saves an unfinished-match report.

**CONTROLS** reads current bindings. **OPTIONS** adjusts sound, display, flashes,
and preview contrast. New installs start with high-contrast previews.
The public demo focuses on keyboard/mouse solo play; touch controls are retained.
**ONLINE** is a separate private-room test: both players need the same build.
Its hidden-plan matches should be evaluated separately from CPU results.

## Feedback

Use **SEND FEEDBACK** on the title or result screen. Describe what you tried,
what happened, and whether you wanted another match. The email destination is
**patochaos@gmail.com**. Opening a draft never sends it automatically.

You can include the latest local report. **OPEN EMAIL DRAFT** copies the complete
feedback/report and opens your mail app; paste the copied report before sending.
If no mail app is available, **COPY FEEDBACK** and paste it into webmail.
Include a screenshot or recording if it helps explain a confusing outcome.

Logging stays on your device until you share it. Options can disable logging,
and the feedback form lets you exclude the report. A browser closed abruptly
may leave an `in_progress` checkpoint rather than a confirmed abandonment.

## Developer access

`Play.bat -- --dev-tools` exposes **EXPERIMENTS** and **CUSTOM MATCH**. Normal
source play and exports use the focused public menu. Tests remain in the source
project and are excluded from exports. No archive is required for local play.
