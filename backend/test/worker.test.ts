import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { createRoom, ORIGIN as origin, post } from "./harness";

describe("room HTTP API", () => {
  it("creates and joins a room", async () => {
    const created = await exports.default.fetch(new Request("https://example.test/rooms", {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: origin },
      body: JSON.stringify({ level: 2, weapon: 2, protocol: 2 }),
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

    const joined = await post(`/rooms/${payload.room}/join`, { weapon: 4, protocol: 2 });
    expect(joined.status).toBe(200);
    await expect(joined.json()).resolves.toMatchObject({
      room: payload.room, player: 1, weapon: 4,
    });

    const third = await post(`/rooms/${payload.room}/join`, { weapon: 0, protocol: 2 });
    expect(third.status).toBe(409);
  });

  it("rejects untrusted browser origins", async () => {
    const response = await exports.default.fetch(new Request("https://example.test/rooms", {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: "https://evil.example" },
      body: JSON.stringify({ level: 0, weapon: 0, protocol: 2 }),
    }));
    expect(response.status).toBe(403);
  });

  it("rejects character ids that are not in the online roster", async () => {
    const response = await post("/rooms", { level: 0, weapon: 99, protocol: 2 });
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
    const response = await post("/rooms", { level: 0, weapon: 0, protocol: 3 });
    expect(response.status).toBe(400);
    const body = await response.json<{ error: string; protocol: number }>();
    expect(body.error).toContain("protocol 2");
    expect(body.error).toContain("client sent 3");
    expect(body.protocol).toBe(2);
  });

  it("rate limits repeated join attempts on one room", async () => {
    const room = await createRoom(0, 0);
    const statuses: number[] = [];
    for (let attempt = 0; attempt < 12; attempt += 1) {
      const response = await post(`/rooms/${room.room}/join`, { weapon: 0, protocol: 2 });
      statuses.push(response.status);
    }
    expect(statuses[0]).toBe(200);
    expect(statuses.slice(1, 10).every((status) => status === 409)).toBe(true);
    expect(statuses.slice(10)).toEqual([429, 429]);
  });
});
