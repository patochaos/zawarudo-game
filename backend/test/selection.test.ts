import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterAll, describe, expect, it } from "vitest";
import { PROTOCOL_VERSION } from "../src/protocol";
import { CLOSE_ROOM_CLOSED, CLOSE_SEAT_LOST, resolveVote } from "../src/room";
import { digest, post, settle, TestSocket } from "./harness";

afterAll(async () => {
  await settle();
});

async function create(capacity = 2, level = 1): Promise<{ room: string; token: string }> {
  const response = await post("/rooms", { level, weapon: 0, capacity, protocol: PROTOCOL_VERSION });
  expect(response.status).toBe(201);
  return response.json<{ room: string; token: string }>();
}

async function join(room: string): Promise<{ status: number; token: string; player: number }> {
  const response = await post(`/rooms/${room}/join`, { weapon: 0, protocol: PROTOCOL_VERSION });
  if (response.status !== 200) return { status: response.status, token: "", player: -1 };
  const body = await response.json<{ token: string; player: number }>();
  return { status: 200, ...body };
}

/** A full two-seat room sitting in the selection phase. */
async function selectingPair(level = 1) {
  const created = await create(2, level);
  const guest = await join(created.room);
  const host = await TestSocket.open(created.room, created.token);
  const guestSocket = await TestSocket.open(created.room, guest.token);
  for (const socket of [host, guestSocket]) {
    expect(await socket.waitFor("selection_state")).toMatchObject({ phase: "selecting" });
    socket.drain();
  }
  return { room: created.room, hostToken: created.token, guestToken: guest.token, host, guest: guestSocket };
}

describe("resolveVote", () => {
  it("takes the majority and breaks a tie among the tied values only", () => {
    expect(resolveVote([2, 2, 5], 0)).toEqual({ value: 2, tied: false });
    for (let i = 0; i < 20; i += 1) {
      const split = resolveVote([2, 5, 2, 5], 0);
      expect(split.tied).toBe(true);
      expect([2, 5]).toContain(split.value);
    }
    expect(resolveVote([], 3)).toEqual({ value: 3, tied: false });
  });
});

describe("protocol 4 selection phase", () => {
  it("opens picks once the room is full and starts on the voted arena, lives and fighters", async () => {
    const { room, host, guest } = await selectingPair(1);
    try {
      expect(host.types()).not.toContain("match_start");
      host.send({ type: "select", weapon: 2, level: 4, lives: 7, ready: true });
      expect(await guest.waitFor("selection_state")).toMatchObject({
        weapons: [2, 0], level_votes: [4, 1], lives_votes: [7, 5], ready: [true, false],
      });
      await settle();
      expect((await env.ROOMS.getByName(room).getInfo()).phase).toBe("selecting");
      guest.send({ type: "select", weapon: 3, level: 4, lives: 3, ready: true });
      for (const socket of [host, guest]) {
        const start = await socket.waitFor("match_start");
        expect(start).toMatchObject({ level: 4, level_tied: false, lives_tied: true, weapons: [2, 3], turn: 1 });
        expect([3, 7]).toContain(start.lives);
      }
      expect((await env.ROOMS.getByName(room).getInfo()).phase).toBe("planning");
    } finally {
      host.close();
      guest.close();
    }
  });

  it("refuses picks outside the selection phase and malformed picks", async () => {
    const created = await create(2);
    const host = await TestSocket.open(created.room, created.token);
    try {
      host.send({ type: "select", weapon: 0, level: 0, lives: 5, ready: true });
      await host.waitForError("wrong_phase");
      host.send({ type: "select", weapon: 0, level: 0, lives: 4, ready: true });
      await host.waitForError("invalid_message");
    } finally {
      host.close();
    }
  });

  it("returns to the selection screen after a rematch instead of starting at once", async () => {
    const { room, host, guest } = await selectingPair(1);
    try {
      for (const socket of [host, guest]) socket.send({ type: "select", weapon: 0, level: 2, lives: 3, ready: true });
      for (const socket of [host, guest]) await socket.waitFor("match_start");
      for (const socket of [host, guest]) socket.sendPlan(1);
      for (const socket of [host, guest]) await socket.waitFor("turn_plans");
      for (const socket of [host, guest]) socket.send({ type: "match_over", turn: 1, winner: 0, digest: digest("c") });
      for (const socket of [host, guest]) await socket.waitFor("match_over");
      for (const socket of [host, guest]) socket.drain();
      for (const socket of [host, guest]) socket.send({ type: "rematch", level: 0 });
      for (const socket of [host, guest]) {
        // Earlier picks survive as the starting point; only the ready flags reset.
        expect(await socket.waitFor("selection_state")).toMatchObject({
          phase: "selecting", level_votes: [2, 2], ready: [false, false],
        });
      }
      await settle();
      expect(host.types()).not.toContain("match_start");
      expect((await env.ROOMS.getByName(room).getInfo()).phase).toBe("selecting");
    } finally {
      host.close();
      guest.close();
    }
  });
});

describe("leaving a protocol 4 room", () => {
  it("frees a guest seat for the next player and sends the room back to waiting", async () => {
    const { room, host, guest } = await selectingPair();
    try {
      guest.send({ type: "leave" });
      expect(await host.waitFor("peer_left")).toMatchObject({ player: 1 });
      expect(await host.waitFor("room_state")).toMatchObject({ phase: "waiting", seated: [true, false] });
      expect(await guest.waitForClose()).toBe(1000);

      const next = await join(room);
      expect(next).toMatchObject({ status: 200, player: 1 });
      const nextSocket = await TestSocket.open(room, next.token);
      expect(await host.waitFor("selection_state")).toMatchObject({ phase: "selecting" });
      nextSocket.close();
    } finally {
      host.close();
      guest.close();
    }
  });

  it("closes the room for everyone when the host leaves", async () => {
    const { room, guestToken, host, guest } = await selectingPair();
    try {
      host.send({ type: "leave" });
      await guest.waitFor("room_closed");
      expect(await guest.waitForClose()).toBe(CLOSE_ROOM_CLOSED);
      // A reconnect to a closed room is told so instead of retrying forever.
      const again = await TestSocket.open(room, guestToken);
      expect(await again.waitForClose()).toBe(CLOSE_ROOM_CLOSED);
      expect((await post(`/rooms/${room}/join`, { weapon: 0, protocol: PROTOCOL_VERSION })).status).toBe(404);
    } finally {
      host.close();
      guest.close();
    }
  });

  it("hands a long-abandoned guest seat to a new player, never a fresh one", async () => {
    const created = await create(4);
    const host = await TestSocket.open(created.room, created.token);
    const seats = [await join(created.room), await join(created.room), await join(created.room)];
    expect(seats.map((seat) => seat.player)).toEqual([1, 2, 3]);
    const dropped = await TestSocket.open(created.room, seats[0]!.token);
    dropped.close();
    await settle();
    try {
      // Inside the grace window the seat is still theirs.
      expect((await join(created.room)).status).toBe(409);
      const stub = env.ROOMS.getByName(created.room);
      await runInDurableObject(stub, (_instance, state) => {
        state.storage.sql.exec("UPDATE participants SET last_seen = 0 WHERE slot = 1");
      });
      expect(await join(created.room)).toMatchObject({ status: 200, player: 1 });
      // The evicted token now gets a definite answer rather than an endless retry loop.
      const ghost = await TestSocket.open(created.room, seats[0]!.token);
      expect(await ghost.waitForClose()).toBe(CLOSE_SEAT_LOST);
    } finally {
      host.close();
    }
  });
});
