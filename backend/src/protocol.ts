export const MAX_PLAN_TICKS = 180;
export const ROOM_CODE_PATTERN = /^[A-HJ-NP-Z2-9]{6}$/;
export const TOKEN_PATTERN = /^[a-f0-9]{64}$/;
export const DIGEST_PATTERN = /^[a-f0-9]{64}$/;

export type PlayerSlot = 0 | 1;

export interface PlayerPlanPayload {
  dirs: number[];
  jumps: number[];
  holds: number[];
  shot_tick: number;
  aim_angle: number;
  power: number;
  super_shot: boolean;
}

export type ClientMessage =
  | { type: "plan"; turn: number; plan: PlayerPlanPayload }
  | { type: "turn_complete"; turn: number; digest: string }
  | { type: "match_over"; turn: number; winner: PlayerSlot; digest: string }
  | { type: "rematch" };

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
  if (dirs === null || jumps === null || holds === null
      || dirs.length !== jumps.length || dirs.length !== holds.length) {
    return null;
  }
  if (!isIntegerInRange(value.shot_tick, -1, MAX_PLAN_TICKS)) {
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
  if (typeof value.super_shot !== "boolean") {
    return null;
  }

  return {
    dirs,
    jumps,
    holds,
    shot_tick: value.shot_tick,
    aim_angle: value.aim_angle,
    power: value.power,
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
    return { type: "rematch" };
  }
  return null;
}

export function parseConnectionAttachment(value: unknown): ConnectionAttachment | null {
  if (!isRecord(value) || (value.slot !== 0 && value.slot !== 1)) {
    return null;
  }
  return { slot: value.slot };
}
