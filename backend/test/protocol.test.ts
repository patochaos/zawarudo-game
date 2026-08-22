import { describe, expect, it } from "vitest";
import { MAX_PLAN_TICKS, parseClientMessage, parsePlan } from "../src/protocol";

const validPlan = {
  dirs: [0, 1, 2],
  jumps: [0, 1, 0],
  holds: [0, 1, 1],
  drops: [0, 0, 1],
  shot_tick: 2,
  aim_angle: 42.5,
  power: 0.75,
  attack_mode: 1,
  super_shot: false,
};

function ticks(count: number): number[] {
  return Array<number>(count).fill(0);
}

describe("plan protocol", () => {
  it("accepts a bounded deterministic plan", () => {
    expect(parsePlan(validPlan)).toEqual(validPlan);
    expect(parseClientMessage(JSON.stringify({ type: "plan", turn: 3, plan: validPlan })))
      .toEqual({ type: "plan", turn: 3, plan: validPlan });
  });

  it("rejects mismatched recordings and invalid bytes", () => {
    expect(parsePlan({ ...validPlan, jumps: [0] })).toBeNull();
    expect(parsePlan({ ...validPlan, drops: [0] })).toBeNull();
    expect(parsePlan({ ...validPlan, dirs: [3] })).toBeNull();
    expect(parsePlan({ ...validPlan, power: 1.01 })).toBeNull();
    expect(parsePlan({ ...validPlan, attack_mode: 2 })).toBeNull();
    expect(parsePlan({ ...validPlan, super_shot: 1 })).toBeNull();
  });

  it("rejects payloads that omit a required field", () => {
    const { drops: _drops, attack_mode: _mode, ...legacy } = validPlan;
    expect(parsePlan(legacy)).toBeNull();
    expect(parsePlan({ ...validPlan, drops: undefined })).toBeNull();
    expect(parsePlan({ ...validPlan, attack_mode: undefined })).toBeNull();
  });

  it("strips the grenade fuse the game no longer has", () => {
    expect(parsePlan({ ...validPlan, grenade_fuse_seconds: 2 }))
      .toEqual(validPlan);
  });

  it("holds plans to the client movement tick budget", () => {
    expect(MAX_PLAN_TICKS).toBe(30);
    const budget = {
      ...validPlan,
      dirs: ticks(MAX_PLAN_TICKS),
      jumps: ticks(MAX_PLAN_TICKS),
      holds: ticks(MAX_PLAN_TICKS),
      drops: ticks(MAX_PLAN_TICKS),
      shot_tick: MAX_PLAN_TICKS,
    };
    expect(parsePlan(budget)).toEqual(budget);

    const overLong = {
      ...budget,
      dirs: ticks(MAX_PLAN_TICKS + 1),
      jumps: ticks(MAX_PLAN_TICKS + 1),
      holds: ticks(MAX_PLAN_TICKS + 1),
      drops: ticks(MAX_PLAN_TICKS + 1),
    };
    expect(parsePlan(overLong)).toBeNull();
  });

  it("keeps the shot inside the recorded plan", () => {
    expect(parsePlan({ ...validPlan, shot_tick: -1 })).toEqual({ ...validPlan, shot_tick: -1 });
    expect(parsePlan({ ...validPlan, shot_tick: 3 })).toEqual({ ...validPlan, shot_tick: 3 });
    expect(parsePlan({ ...validPlan, shot_tick: 4 })).toBeNull();
    expect(parsePlan({ ...validPlan, shot_tick: -2 })).toBeNull();
  });

  it("rejects unknown and malformed messages", () => {
    expect(parseClientMessage("not json")).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: "admin" }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: "turn_complete", turn: 1, digest: "bad" })))
      .toBeNull();
  });

  it("requires a level on every rematch request", () => {
    expect(parseClientMessage(JSON.stringify({ type: "rematch", level: 1 })))
      .toEqual({ type: "rematch", level: 1 });
    expect(parseClientMessage(JSON.stringify({ type: "rematch" }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: "rematch", level: null }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: "rematch", level: -1 }))).toBeNull();
  });
});
