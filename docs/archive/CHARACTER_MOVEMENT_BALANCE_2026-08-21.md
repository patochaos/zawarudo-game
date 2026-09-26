# Character movement balance — 2026-08-21

This pass makes locomotion part of the four selectable class identities instead
of giving every fighter the same vertical physics. Values below use the default
260 px/s base walk speed, 780 px/s base jump impulse, 1400 px/s² gravity, and
1200 px/s base fall cap.

| Class | Full jump rise | Air jump rise | Walk speed | Fall cap | Intent |
|---|---:|---:|---:|---:|---|
| Dagger Duelist | 217 px | 146 px, one charge | 260 px/s | 1200 px/s | Flexible reference character |
| The Velocity | None | None | 234 px/s | 1320 px/s | Ground-bound; aimed CUT TO END is her vertical movement |
| The Static Witch | 176 px | None | 234 px/s | 1020 px/s | Floaty, readable single-jump zoner |
| Broodtail | 263 px | 113 px, one charge | 273 px/s | 1080 px/s | Most agile conventional platformer |

The rises are continuous-physics approximations (`impulse² / 2g`); fixed-tick
collision and releasing jump early make the observed route slightly smaller.

## Why Velocity has no jump

Velocity already owns a freely aimed 660–980 px/s body dash lasting 8–15 ticks,
with up to three extra ticks from Lost Frames. Letting that attack be her only
way to climb gives the class a real constraint without making upper terrain
inaccessible. Going upward now costs her attack for the turn, exposes a committed
line, and risks the faster descent afterward. The first tournament showed that
75% walk plus no jump was too punitive, including a 0–14 matchup into Broodtail.
The retained 90% walk keeps a visible Lost Frames penalty without making every
ground approach glacial. Frame Debt's cell distance was reduced proportionally,
so the movement buff does not quietly nerf her attack resource.

## Simulation evidence

The initial two-seed, seven-arena duel matrix used the no-jump profile with 75%
walk, 125% fall, and the Witch's more extreme float. Across 84 matches it found
7 unresolved and these win totals: Dagger 20/42, Velocity 12/42, Static Witch
31/42, and Broodtail 14/42. Velocity was healthy into Dagger (7–6) and playable
into Witch (5–9), but Broodtail won the matchup 14–0.

The revised one-seed directional check covered all 42 arena/pairing combinations.
It found 4 unresolved and these win totals: Dagger 7/21, Velocity 9/21, Static
Witch 15/21, and Broodtail 7/21. Velocity improved to 42.9% overall and went 3–4
into Witch, but the Broodtail counter persisted at 7–0 while Velocity swung to
6–1 over Dagger.

That second result is a guardrail against further universal movement buffs.
Broodtail–Velocity needs a weapon-interaction review; more walk speed would
mainly make Velocity oppressive in the matchups that are already functional.
Static Witch's remaining 71.4% lead likewise points beyond locomotion to her
plasma/orb kit. Tournament AI is directional evidence, not a replacement for
human matchup playtests.

## Tuning surface

All values are exported under **Class Movement** in `GameManager.gd`. Each class
has independent walk, ground-jump, air-jump, air-jump-count, and fall-cap scales.
The scales multiply the shared movement tuning, so the Free Play tuning screen
can still adjust the whole roster without erasing class differences.

Live play, planning ghosts, AI forecasts, execution, respawns, and replay restore
all read the same profile functions. A forbidden jump is rejected rather than
recorded as a tiny jump, which keeps prediction and online replay deterministic.

## First playtest watch points

- Velocity must still reach contested upper tiers often enough through diagonal
  CUT TO END. If not, inspect dash routing before restoring a jump or raising
  universal walk speed.
- Broodtail's strong first jump plus weak air jump may be too evasive alongside
  a persistent weapon. The first nerf should be the 1.05 walk scale, not jump
  height, because the high arc is the clearer class signature.
- Static Witch's 0.85 fall scale should remain readable without recreating the
  excessive safety seen at 0.72. Her weapon kit, not movement, is the next place
  to look if her tournament lead persists.
- Dagger is the reference. Change its profile only if every other class is being
  tuned around an obviously unhealthy baseline.
- Broodtail currently hard-counters Velocity in the AI matrix despite losing to
  the other two kits. Review chakram-versus-dash counterplay as a matchup rule,
  not as another broad locomotion change.
