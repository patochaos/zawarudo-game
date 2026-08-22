import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

describe("Room durable object", () => {
  it("reserves a room once and assigns the guest slot", async () => {
    const room = env.ROOMS.getByName("ABC234");
    expect(await room.reserve("ABC234", "a".repeat(64), 1, 1234, 2, 2)).toBe(true);
    expect(await room.reserve("ABC234", "b".repeat(64), 2, 9999, 3)).toBe(false);

    expect(await room.join("c".repeat(64), 4, 2)).toEqual({ ok: true, player: 1 });
    expect(await room.join("d".repeat(64))).toEqual({ ok: false, reason: "full" });
    expect(await room.getInfo()).toEqual({
      exists: true,
      phase: "waiting",
      level: 1,
      seed: 1234,
      turn: 1,
      hasGuest: true,
      weapons: [2, 4],
    });
  });

  it("falls back to Duelists when either client predates character sync", async () => {
    const room = env.ROOMS.getByName("OLD234");
    expect(await room.reserve("OLD234", "e".repeat(64), 6, 5678, 2, 2)).toBe(true);
    expect(await room.join("f".repeat(64))).toEqual({ ok: true, player: 1 });
    expect((await room.getInfo()).weapons).toEqual([0, 0]);
  });
});
