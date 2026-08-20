import { describe, expect, it } from "vitest";
import { parseClientMessage, parsePlan } from "../src/protocol";

const validPlan = {
  dirs: [0, 1, 2],
  jumps: [0, 1, 0],
  holds: [0, 1, 1],
  shot_tick: 2,
  aim_angle: 42.5,
  power: 0.75,
  super_shot: false,
};

describe("plan protocol", () => {
  it("accepts a bounded deterministic plan", () => {
    expect(parsePlan(validPlan)).toEqual(validPlan);
    expect(parseClientMessage(JSON.stringify({ type: "plan", turn: 3, plan: validPlan })))
      .toEqual({ type: "plan", turn: 3, plan: validPlan });
  });

  it("rejects mismatched recordings and invalid bytes", () => {
    expect(parsePlan({ ...validPlan, jumps: [0] })).toBeNull();
    expect(parsePlan({ ...validPlan, dirs: [3] })).toBeNull();
    expect(parsePlan({ ...validPlan, power: 1.01 })).toBeNull();
  });

  it("rejects unknown and malformed messages", () => {
    expect(parseClientMessage("not json")).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: "admin" }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ type: "turn_complete", turn: 1, digest: "bad" })))
      .toBeNull();
  });

  it("accepts a host-selected rematch level while preserving legacy clients", () => {
    expect(parseClientMessage(JSON.stringify({ type: "rematch", level: 1 })))
      .toEqual({ type: "rematch", level: 1 });
    expect(parseClientMessage(JSON.stringify({ type: "rematch" })))
      .toEqual({ type: "rematch", level: null });
    expect(parseClientMessage(JSON.stringify({ type: "rematch", level: -1 })))
      .toBeNull();
  });
});
