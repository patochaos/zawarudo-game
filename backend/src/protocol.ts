// The wire contract version. The Worker requires an exact match on create and join so a stale
// browser tab is told to reload instead of joining a match it cannot simulate.
export const PROTOCOL_VERSION = 2;

// The client records at most `movement_tick_budget()` ticks of movement, which is
// ceil(movement_budget * physics_ticks_per_second) = ceil(0.50 * 60) = 30, and it hard-stops the
// match when a peer plan is longer than that budget. The server must reject over-long plans for
// the same reason: relaying one is a denial-of-match against the honest client.
// MUST stay in sync with GameManager.movement_tick_budget() / movement_budget on the client.
export const MOVEMENT_BUDGET_SECONDS = 0.50;
export const PHYSICS_TICKS_PER_SECOND = 60;
export const MAX_PLAN_TICKS = Math.ceil(MOVEMENT_BUDGET_SECONDS * PHYSICS_TICKS_PER_SECOND);

export const ROOM_CODE_PATTERN = /^[A-HJ-NP-Z2-9]{6}$/;
export const TOKEN_PATTERN = /^[a-f0-9]{64}$/;
export const DIGEST_PATTERN = /^[a-f0-9]{64}$/;

export type PlayerSlot = 0 | 1;

export interface PlayerPlanPayload {
  dirs: number[];
  jumps: number[];
  holds: number[];
  drops: number[];
  shot_tick: number;
  aim_angle: number;
  power: number;
  attack_mode: number;
  super_shot: boolean;
}

export type ClientMessage =
  | { type: "plan"; turn: number; plan: PlayerPlanPayload }
  | { type: "turn_complete"; turn: number; digest: string }
  | { type: "match_over"; turn: number; winner: PlayerSlot; digest: string }
  | { type: "rematch"; level: number };

export interface ConnectionAttachment {
  slot: PlayerSlot;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isIntegerInRange(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number"
    && Number.isInteger(value)
    && value >= minimum
    && value <= maximum;
}

function parseByteArray(value: unknown, maximum: number): number[] | null {
  if (!Array.isArray(value) || value.length > MAX_PLAN_TICKS) {
    return null;
  }
  const parsed: number[] = [];
  for (const item of value) {
    if (!isIntegerInRange(item, 0, maximum)) {
      return null;
    }
    parsed.push(item);
  }
  return parsed;
}

export function parsePlan(value: unknown): PlayerPlanPayload | null {
  if (!isRecord(value)) {
    return null;
  }

  const dirs = parseByteArray(value.dirs, 2);
  const jumps = parseByteArray(value.jumps, 1);
  const holds = parseByteArray(value.holds, 1);
  const drops = parseByteArray(value.drops, 1);
  if (dirs === null || jumps === null || holds === null
      || drops === null || dirs.length !== jumps.length || dirs.length !== holds.length
      || dirs.length !== drops.length) {
    return null;
  }
  if (!isIntegerInRange(value.shot_tick, -1, dirs.length)) {
    return null;
  }
  if (typeof value.aim_angle !== "number" || !Number.isFinite(value.aim_angle)
      || value.aim_angle < -360 || value.aim_angle > 360) {
    return null;
  }
  if (typeof value.power !== "number" || !Number.isFinite(value.power)
      || value.power < 0 || value.power > 1) {
    return null;
  }
  if (!isIntegerInRange(value.attack_mode, 0, 1)) {
    return null;
  }
  if (typeof value.super_shot !== "boolean") {
    return null;
  }

  return {
    dirs,
    jumps,
    holds,
    drops,
    shot_tick: value.shot_tick,
    aim_angle: value.aim_angle,
    power: value.power,
    attack_mode: value.attack_mode,
    super_shot: value.super_shot,
  };
}

export function parseClientMessage(text: string): ClientMessage | null {
  if (text.length > 16_384) {
    return null;
  }

  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isRecord(value) || typeof value.type !== "string") {
    return null;
  }

  if (value.type === "plan") {
    const plan = parsePlan(value.plan);
    if (!isIntegerInRange(value.turn, 1, 1_000_000) || plan === null) {
      return null;
    }
    return { type: "plan", turn: value.turn, plan };
  }
  if (value.type === "turn_complete") {
    if (!isIntegerInRange(value.turn, 1, 1_000_000)
        || typeof value.digest !== "string" || !DIGEST_PATTERN.test(value.digest)) {
      return null;
    }
    return { type: "turn_complete", turn: value.turn, digest: value.digest };
  }
  if (value.type === "match_over") {
    if (!isIntegerInRange(value.turn, 1, 1_000_000)
        || !isIntegerInRange(value.winner, 0, 1)
        || typeof value.digest !== "string" || !DIGEST_PATTERN.test(value.digest)) {
      return null;
    }
    return {
      type: "match_over",
      turn: value.turn,
      winner: value.winner === 0 ? 0 : 1,
      digest: value.digest,
    };
  }
  if (value.type === "rematch") {
    if (!isIntegerInRange(value.level, 0, 63)) {
      return null;
    }
    return { type: "rematch", level: value.level };
  }
  return null;
}

export function parseConnectionAttachment(value: unknown): ConnectionAttachment | null {
  if (!isRecord(value) || (value.slot !== 0 && value.slot !== 1)) {
    return null;
  }
  return { slot: value.slot };
}
