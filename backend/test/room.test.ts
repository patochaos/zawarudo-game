import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import {
  createRoom,
  digest,
  joinRoom,
  type MatchFixture,
  playTurn,
  post,
  settle,
  startMatch,
  TestSocket,
} from "./harness";

describe("Room durable object", () => {
  it("reserves a room once and assigns the guest slot", async () => {
    const room = env.ROOMS.getByName("ABC234");
    expect(await room.reserve("ABC234", "a".repeat(64), 1, 1234, 2)).toBe(true);
    expect(await room.reserve("ABC234", "b".repeat(64), 2, 9999, 3)).toBe(false);

    expect(await room.join("c".repeat(64), 4)).toEqual({ ok: true, player: 1 });
    expect(await room.join("d".repeat(64), 0)).toEqual({ ok: false, reason: "full" });
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

  it("rejects clients that do not speak the current protocol", async () => {
    const stale = await post("/rooms", { level: 6, weapon: 2, protocol: 1 });
    expect(stale.status).toBe(400);
    await expect(stale.json<{ error: string }>()).resolves.toMatchObject({
      error: expect.stringContaining("Protocol version mismatch") as unknown as string,
      protocol: 2,
    });

    const created = await createRoom(6, 2);
    const joined = await post(`/rooms/${created.room}/join`, { weapon: 4, protocol: 1 });
    expect(joined.status).toBe(400);
    // The stale guest never lands, and the host keeps the fighter it picked: there is no
    // silent downgrade of both players to Duelists any more.
    expect((await env.ROOMS.getByName(created.room).getInfo()).weapons).toEqual([2, 0]);
  });
});

describe("lockstep turn cycle", () => {
  it("starts the match once both sockets are connected", async () => {
    const created = await createRoom(3, 2);
    const guestToken = await post(`/rooms/${created.room}/join`, { weapon: 4, protocol: 2 })
      .then((response) => response.json<{ token: string }>())
      .then((body) => body.token);

    const host = await TestSocket.open(created.room, created.token);
    expect(await host.waitFor("connected")).toMatchObject({ room: created.room, player: 0 });
    expect(await host.waitFor("room_state")).toMatchObject({ phase: "waiting", level: 3 });
    await settle();
    expect(host.types()).not.toContain("match_start");

    const guest = await TestSocket.open(created.room, guestToken);
    expect(await host.waitFor("match_start")).toMatchObject({
      level: 3, turn: 1, weapons: [2, 4],
    });
    expect(await guest.waitFor("match_start")).toMatchObject({ level: 3, turn: 1 });

    host.close();
    guest.close();
  });

  it("advances a turn when both plans and matching digests arrive", async () => {
    const fixture = await startMatch();

    fixture.host.sendPlan(1, { dirs: [1, 1], jumps: [0, 0], holds: [0, 0], drops: [0, 0] });
    expect(await fixture.host.waitFor("plan_ack")).toMatchObject({ turn: 1 });
    fixture.guest.sendPlan(1, { attack_mode: 1 });
    expect(await fixture.guest.waitFor("plan_ack")).toMatchObject({ turn: 1 });

    const hostPlans = await fixture.host.waitFor("turn_plans");
    const guestPlans = await fixture.guest.waitFor("turn_plans");
    expect(hostPlans).toEqual(guestPlans);
    expect(hostPlans.turn).toBe(1);
    const plans = hostPlans.plans as Record<string, unknown>[];
    expect(plans).toHaveLength(2);
    expect(plans[0]).toMatchObject({ dirs: [1, 1] });
    expect(plans[1]).toMatchObject({ attack_mode: 1 });
    expect(plans[0]).not.toHaveProperty("grenade_fuse_seconds");
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("executing");

    fixture.host.send({ type: "turn_complete", turn: 1, digest: digest("1") });
    expect(await fixture.host.waitFor("turn_complete_ack")).toMatchObject({ turn: 1 });
    fixture.guest.send({ type: "turn_complete", turn: 1, digest: digest("1") });

    expect(await fixture.host.waitFor("turn_start")).toMatchObject({ turn: 2 });
    expect(await fixture.guest.waitFor("turn_start")).toMatchObject({ turn: 2 });
    expect(await env.ROOMS.getByName(fixture.room).getInfo()).toMatchObject({
      phase: "planning", turn: 2,
    });

    fixture.host.close();
    fixture.guest.close();
  });

  it("keeps a plan private until both plans are in", async () => {
    const fixture = await startMatch();

    fixture.host.sendPlan(1, { aim_angle: 123.5 });
    await fixture.host.waitFor("plan_ack");
    await settle();

    expect(fixture.guest.types()).not.toContain("turn_plans");
    expect(JSON.stringify(fixture.guest.received)).not.toContain("123.5");
    expect(fixture.host.types()).not.toContain("turn_plans");
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("planning");

    fixture.guest.sendPlan(1);
    await fixture.guest.waitFor("turn_plans");
    await fixture.host.waitFor("turn_plans");

    fixture.host.close();
    fixture.guest.close();
  });

  it("desyncs the room when turn digests disagree", async () => {
    const fixture = await startMatch();
    fixture.host.sendPlan(1);
    fixture.guest.sendPlan(1);
    await fixture.host.waitFor("turn_plans");
    await fixture.guest.waitFor("turn_plans");

    fixture.host.send({ type: "turn_complete", turn: 1, digest: digest("a") });
    fixture.guest.send({ type: "turn_complete", turn: 1, digest: digest("b") });

    expect(await fixture.host.waitFor("desync")).toMatchObject({ turn: 1 });
    expect(await fixture.guest.waitFor("desync")).toMatchObject({ turn: 1 });
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("desync");
    await settle();
    expect(fixture.host.types()).not.toContain("turn_start");

    fixture.host.close();
    fixture.guest.close();
  });

  it("desyncs the room when the reported winner or digest disagrees", async () => {
    const fixture = await startMatch();
    fixture.host.sendPlan(1);
    fixture.guest.sendPlan(1);
    await fixture.host.waitFor("turn_plans");
    await fixture.guest.waitFor("turn_plans");

    fixture.host.send({ type: "match_over", turn: 1, winner: 0, digest: digest("a") });
    expect(await fixture.host.waitFor("match_over_ack")).toMatchObject({ turn: 1 });
    fixture.guest.send({ type: "match_over", turn: 1, winner: 1, digest: digest("a") });

    await fixture.host.waitFor("desync");
    await fixture.guest.waitFor("desync");
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("desync");

    fixture.host.close();
    fixture.guest.close();
  });

  it("ends the match when both clients report the same result", async () => {
    const fixture = await startMatch();
    fixture.host.sendPlan(1);
    fixture.guest.sendPlan(1);
    await fixture.host.waitFor("turn_plans");
    await fixture.guest.waitFor("turn_plans");

    fixture.host.send({ type: "match_over", turn: 1, winner: 1, digest: digest("c") });
    fixture.guest.send({ type: "match_over", turn: 1, winner: 1, digest: digest("c") });

    expect(await fixture.host.waitFor("match_over")).toMatchObject({ turn: 1, winner: 1 });
    expect(await fixture.guest.waitFor("match_over")).toMatchObject({ turn: 1, winner: 1 });
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("game_over");

    fixture.host.close();
    fixture.guest.close();
  });

  it("restarts the match only once both slots are ready for a rematch", async () => {
    const fixture = await startMatch(1);
    await playTurn(fixture, 1);
    fixture.host.sendPlan(2);
    fixture.guest.sendPlan(2);
    await fixture.host.waitFor("turn_plans");
    await fixture.guest.waitFor("turn_plans");
    fixture.host.send({ type: "match_over", turn: 2, winner: 0, digest: digest("d") });
    fixture.guest.send({ type: "match_over", turn: 2, winner: 0, digest: digest("d") });
    await fixture.host.waitFor("match_over");
    await fixture.guest.waitFor("match_over");

    // Slot 1 cannot move the room to another level, and one side alone does not restart.
    fixture.guest.send({ type: "rematch", level: 9 });
    expect(await fixture.host.waitFor("rematch_status")).toEqual({
      type: "rematch_status", ready: [1], level: 1,
    });
    await settle();
    expect(fixture.host.types()).not.toContain("match_start");
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("game_over");

    fixture.host.send({ type: "rematch", level: 4 });
    expect(await fixture.host.waitFor("rematch_status")).toMatchObject({ ready: [0, 1], level: 4 });
    const restart = await fixture.host.waitFor("match_start");
    expect(restart).toMatchObject({ level: 4, turn: 1 });
    expect(restart.seed).not.toBe(fixture.seed);
    await fixture.guest.waitFor("match_start");
    expect(await env.ROOMS.getByName(fixture.room).getInfo()).toMatchObject({
      phase: "planning", turn: 1, level: 4,
    });

    // Tables were cleared: the stale turn-1 plans do not fire a turn_plans broadcast.
    fixture.host.drain();
    fixture.guest.drain();
    fixture.host.sendPlan(1);
    await fixture.host.waitFor("plan_ack");
    await settle();
    expect(fixture.guest.types()).not.toContain("turn_plans");

    fixture.host.close();
    fixture.guest.close();
  });

  it("rejects messages that arrive in the wrong phase", async () => {
    const fixture = await startMatch();

    fixture.host.send({ type: "turn_complete", turn: 1, digest: digest("a") });
    expect(await fixture.host.waitForError("wrong_phase")).toMatchObject({ type: "error" });
    fixture.host.send({ type: "rematch", level: 2 });
    await fixture.host.waitForError("wrong_phase");
    expect(await env.ROOMS.getByName(fixture.room).getInfo()).toMatchObject({
      phase: "planning", turn: 1, level: 1,
    });

    fixture.host.sendPlan(1);
    fixture.guest.sendPlan(1);
    await fixture.host.waitFor("turn_plans");
    await fixture.guest.waitFor("turn_plans");

    fixture.host.drain();
    fixture.guest.drain();
    fixture.host.sendPlan(1, { aim_angle: -90 });
    await fixture.host.waitForError("wrong_phase");
    await settle();
    expect(fixture.guest.types()).not.toContain("turn_plans");
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("executing");

    fixture.host.close();
    fixture.guest.close();
  });

  it("rejects a plan payload the client build could never produce", async () => {
    const fixture = await startMatch();
    const overLong = Array<number>(40).fill(0);

    fixture.host.send({
      type: "plan",
      turn: 1,
      plan: {
        dirs: overLong, jumps: overLong, holds: overLong, drops: overLong,
        shot_tick: 35, aim_angle: 0, power: 0.5, attack_mode: 0, super_shot: false,
      },
    });
    expect(await fixture.host.waitForError("invalid_message")).toMatchObject({ type: "error" });
    await settle();
    expect(fixture.guest.types()).not.toContain("turn_plans");

    fixture.host.close();
    fixture.guest.close();
  });

  it("replaces an earlier socket for the same slot and replays the stored plans", async () => {
    const fixture = await startMatch();
    fixture.host.sendPlan(1);
    fixture.guest.sendPlan(1);
    await fixture.host.waitFor("turn_plans");
    await fixture.guest.waitFor("turn_plans");

    const reconnected = await TestSocket.open(fixture.room, fixture.guestToken);
    expect(await fixture.guest.waitForClose()).toBe(4001);
    expect(await reconnected.waitFor("connected")).toMatchObject({ player: 1 });
    expect(await reconnected.waitFor("turn_plans")).toMatchObject({ turn: 1 });

    reconnected.send({ type: "turn_complete", turn: 1, digest: digest("a") });
    fixture.host.send({ type: "turn_complete", turn: 1, digest: digest("a") });
    expect(await reconnected.waitFor("turn_start")).toMatchObject({ turn: 2 });

    fixture.host.close();
    reconnected.close();
  });

  it("throttles a socket that floods the room", async () => {
    const fixture = await startMatch();
    for (let index = 0; index < 60; index += 1) {
      fixture.host.send({ type: "turn_complete", turn: 1, digest: digest("a") });
    }
    await fixture.host.waitForError("rate_limited");

    // The peer is unaffected by the flood.
    await settle();
    expect(fixture.guest.types()).not.toContain("error");

    fixture.host.close();
    fixture.guest.close();
  });
});

describe("forfeit", () => {
  /** Leaves the host alone in a live match and grants it the win. */
  async function forfeitedMatch(level = 1): Promise<MatchFixture> {
    const fixture = await startMatch(level);
    fixture.guest.close();
    await settle();
    fixture.host.send({ type: "forfeit" });
    await fixture.host.waitFor("opponent_left");
    return fixture;
  }

  it("refuses a forfeit while the peer is still connected", async () => {
    const fixture = await startMatch();

    fixture.host.send({ type: "forfeit" });
    expect(await fixture.host.waitForError("peer_present")).toMatchObject({ type: "error" });
    await settle();
    expect(fixture.guest.types()).not.toContain("opponent_left");
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("planning");

    // No match report was written for the claiming slot: a lone report from the peer is still
    // the only row for this turn, so it is acknowledged instead of counting as a disagreement.
    fixture.host.sendPlan(1);
    fixture.guest.sendPlan(1);
    await fixture.host.waitFor("turn_plans");
    await fixture.guest.waitFor("turn_plans");
    fixture.guest.send({ type: "match_over", turn: 1, winner: 1, digest: digest("e") });
    expect(await fixture.guest.waitFor("match_over_ack")).toMatchObject({ turn: 1 });
    await settle();
    expect(fixture.guest.types()).not.toContain("desync");
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("executing");

    fixture.host.close();
    fixture.guest.close();
  });

  it("grants the win to the claiming slot once the peer is gone", async () => {
    const fixture = await startMatch();
    fixture.host.close();
    await settle();

    fixture.guest.send({ type: "forfeit" });
    expect(await fixture.guest.waitFor("opponent_left")).toEqual({
      type: "opponent_left", winner: 1, turn: 1,
    });
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("game_over");

    fixture.guest.close();
  });

  it("lets the abandoned player reconnect to the finished match", async () => {
    const fixture = await startMatch(2);
    fixture.host.sendPlan(1);
    fixture.guest.sendPlan(1);
    await fixture.host.waitFor("turn_plans");
    await fixture.guest.waitFor("turn_plans");

    // Claimed from `executing`, the phase a mid-turn reload leaves behind.
    fixture.guest.close();
    await settle();
    fixture.host.send({ type: "forfeit" });
    expect(await fixture.host.waitFor("opponent_left")).toEqual({
      type: "opponent_left", winner: 0, turn: 1,
    });

    const back = await TestSocket.open(fixture.room, fixture.guestToken);
    expect(await back.waitFor("connected")).toMatchObject({ player: 1 });
    expect(await back.waitFor("room_state")).toMatchObject({
      phase: "game_over", turn: 1, level: 2,
    });
    await settle();
    expect(back.types()).not.toContain("error");

    fixture.host.close();
    back.close();
  });

  it("still runs the rematch handshake after a forfeit", async () => {
    const fixture = await forfeitedMatch(1);
    const back = await TestSocket.open(fixture.room, fixture.guestToken);
    await back.waitFor("room_state");

    back.send({ type: "rematch", level: 7 });
    expect(await fixture.host.waitFor("rematch_status")).toMatchObject({ ready: [1], level: 1 });
    fixture.host.send({ type: "rematch", level: 5 });
    expect(await fixture.host.waitFor("match_start")).toMatchObject({ level: 5, turn: 1 });
    expect(await back.waitFor("match_start")).toMatchObject({ level: 5, turn: 1 });
    expect(await env.ROOMS.getByName(fixture.room).getInfo()).toMatchObject({
      phase: "planning", turn: 1, level: 5,
    });

    fixture.host.close();
    back.close();
  });

  it("refuses a forfeit before the match has started", async () => {
    const created = await createRoom(1, 0);
    await joinRoom(created.room, 0);
    const host = await TestSocket.open(created.room, created.token);
    expect(await host.waitFor("room_state")).toMatchObject({ phase: "waiting" });

    host.send({ type: "forfeit" });
    await host.waitForError("wrong_phase");
    expect((await env.ROOMS.getByName(created.room).getInfo()).phase).toBe("waiting");

    host.close();
  });

  it("refuses a forfeit once the match is over", async () => {
    const fixture = await startMatch();
    fixture.host.sendPlan(1);
    fixture.guest.sendPlan(1);
    await fixture.host.waitFor("turn_plans");
    await fixture.guest.waitFor("turn_plans");
    fixture.host.send({ type: "match_over", turn: 1, winner: 0, digest: digest("f") });
    fixture.guest.send({ type: "match_over", turn: 1, winner: 0, digest: digest("f") });
    await fixture.host.waitFor("match_over");

    fixture.guest.close();
    await settle();
    fixture.host.send({ type: "forfeit" });
    await fixture.host.waitForError("wrong_phase");
    await settle();
    expect(fixture.host.types()).not.toContain("opponent_left");

    fixture.host.close();
  });

  it("refuses a forfeit after a desync", async () => {
    const fixture = await startMatch();
    fixture.host.sendPlan(1);
    fixture.guest.sendPlan(1);
    await fixture.host.waitFor("turn_plans");
    await fixture.guest.waitFor("turn_plans");
    fixture.host.send({ type: "turn_complete", turn: 1, digest: digest("a") });
    fixture.guest.send({ type: "turn_complete", turn: 1, digest: digest("b") });
    await fixture.host.waitFor("desync");

    fixture.guest.close();
    await settle();
    fixture.host.send({ type: "forfeit" });
    await fixture.host.waitForError("wrong_phase");
    expect((await env.ROOMS.getByName(fixture.room).getInfo()).phase).toBe("desync");

    fixture.host.close();
  });
});
