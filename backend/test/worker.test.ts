import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { createRoom, ORIGIN as origin, post } from "./harness";

describe("room HTTP API", () => {
  it("advertises current and legacy server capabilities", async () => {
    const response = await exports.default.fetch(new Request("https://example.test/health"));
    expect(await response.json()).toMatchObject({ protocol: 4, capacities: [2, 4], legacy_protocol: 2 });
  });

  it("keeps legacy rooms isolated from current clients without consuming their seats", async () => {
    const created = await post("/rooms", { level: 0, weapon: 0, protocol: 2 });
    expect(created.status).toBe(201);
    const legacy = await created.json<{ room: string; capacity: number; protocol: number }>();
    expect(legacy).toMatchObject({ capacity: 2, protocol: 2 });
    expect((await env.ROOMS.getByName(legacy.room).getInfo()).protocol).toBe(2);
    const mismatch = await post(`/rooms/${legacy.room}/join`, { weapon: 0, protocol: 3 });
    expect(mismatch.status).toBe(400);
    expect(await mismatch.json()).toMatchObject({ protocol: 2 });
    const joined = await post(`/rooms/${legacy.room}/join`, { weapon: 0, protocol: 2 });
    expect(joined.status).toBe(200);
    expect(await joined.json()).toMatchObject({ player: 1, capacity: 2, protocol: 2 });
    expect((await post("/rooms", { level: 0, weapon: 0, protocol: 2, capacity: 4 })).status).toBe(400);
  });

  it("rejects legacy joins to current two- and four-player rooms before allocating a seat", async () => {
    for (const capacity of [2, 4]) {
      const current = await createRoom(0, 0, capacity);
      const mismatch = await post(`/rooms/${current.room}/join`, { weapon: 0, protocol: 2 });
      expect(mismatch.status).toBe(400);
      expect(await mismatch.json()).toMatchObject({ protocol: 3 });
      const joined = await post(`/rooms/${current.room}/join`, { weapon: 0, protocol: 3 });
      expect(joined.status).toBe(200);
      expect(await joined.json()).toMatchObject({ player: 1, capacity, protocol: 3 });
    }
  });

  it("rejects unsupported room capacities", async () => {
    for (const capacity of [0, 1, 3, 5, "4", null]) {
      expect((await post("/rooms", { level: 0, weapon: 0, protocol: 3, capacity })).status).toBe(400);
    }
  });

  it("creates and joins a room", async () => {
    const created = await exports.default.fetch(new Request("https://example.test/rooms", {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: origin },
      body: JSON.stringify({ level: 2, weapon: 2, protocol: 3 }),
    }));
    expect(created.status).toBe(201);
    expect(created.headers.get("Access-Control-Allow-Origin")).toBe(origin);

    const payload = await created.json<{
      room: string; token: string; player: number; weapon: number;
    }>();
    expect(payload.room).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
    expect(payload.token).toMatch(/^[a-f0-9]{64}$/);
    expect(payload.player).toBe(0);
    expect(payload.weapon).toBe(2);

    const joined = await post(`/rooms/${payload.room}/join`, { weapon: 4, protocol: 3 });
    expect(joined.status).toBe(200);
    await expect(joined.json()).resolves.toMatchObject({
      room: payload.room, player: 1, weapon: 4,
    });

    const third = await post(`/rooms/${payload.room}/join`, { weapon: 0, protocol: 3 });
    expect(third.status).toBe(409);
  });

  it("accepts the itch.io embed origin", async () => {
    const itch = "https://html-classic.itch.zone";
    const preflight = await exports.default.fetch(new Request("https://example.test/rooms", {
      method: "OPTIONS",
      headers: { Origin: itch, "Access-Control-Request-Method": "POST" },
    }));
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("Access-Control-Allow-Origin")).toBe(itch);
  });

  it("rejects untrusted browser origins", async () => {
    const response = await exports.default.fetch(new Request("https://example.test/rooms", {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: "https://evil.example" },
      body: JSON.stringify({ level: 0, weapon: 0, protocol: 3 }),
    }));
    expect(response.status).toBe(403);
  });

  it("rejects character ids that are not in the online roster", async () => {
    const response = await post("/rooms", { level: 0, weapon: 99, protocol: 3 });
    expect(response.status).toBe(400);
  });

  it("requires the protocol version on create and join", async () => {
    const created = await post("/rooms", { level: 0, weapon: 0 });
    expect(created.status).toBe(400);
    await expect(created.json()).resolves.toEqual({ error: "Invalid room settings" });

    const room = await createRoom(0, 0);
    const joined = await post(`/rooms/${room.room}/join`, { weapon: 0 });
    expect(joined.status).toBe(400);
    await expect(joined.json()).resolves.toEqual({ error: "Invalid fighter" });

    const empty = await exports.default.fetch(
      new Request(`https://example.test/rooms/${room.room}/join`, {
        method: "POST",
        headers: { Origin: origin },
      }),
    );
    expect(empty.status).toBe(400);
  });

  it("names the mismatch when the client speaks a newer protocol", async () => {
    const response = await post("/rooms", { level: 0, weapon: 0, protocol: 5 });
    expect(response.status).toBe(400);
    const body = await response.json<{ error: string; protocol: number }>();
    expect(body.error).toContain("protocol 4");
    expect(body.error).toContain("client sent 5");
    expect(body.protocol).toBe(4);
  });

  it("rate limits repeated join attempts on one room", async () => {
    const room = await createRoom(0, 0);
    const statuses: number[] = [];
    for (let attempt = 0; attempt < 12; attempt += 1) {
      const response = await post(`/rooms/${room.room}/join`, { weapon: 0, protocol: 3 });
      statuses.push(response.status);
    }
    expect(statuses[0]).toBe(200);
    expect(statuses.slice(1, 10).every((status) => status === 409)).toBe(true);
    expect(statuses.slice(10)).toEqual([429, 429]);
  });
});
