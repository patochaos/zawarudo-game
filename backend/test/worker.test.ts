import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

const origin = "https://zawarudo-pi.vercel.app";

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

    const joined = await exports.default.fetch(new Request(`https://example.test/rooms/${payload.room}/join`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: origin },
      body: JSON.stringify({ weapon: 4, protocol: 2 }),
    }));
    expect(joined.status).toBe(200);
    await expect(joined.json()).resolves.toMatchObject({
      room: payload.room, player: 1, weapon: 4,
    });

    const third = await exports.default.fetch(new Request(`https://example.test/rooms/${payload.room}/join`, {
      method: "POST",
      headers: { Origin: origin },
    }));
    expect(third.status).toBe(409);
  });

  it("rejects untrusted browser origins", async () => {
    const response = await exports.default.fetch(new Request("https://example.test/rooms", {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: "https://evil.example" },
      body: JSON.stringify({ level: 0 }),
    }));
    expect(response.status).toBe(403);
  });

  it("rejects character ids that are not in the online roster", async () => {
    const response = await exports.default.fetch(new Request("https://example.test/rooms", {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: origin },
      body: JSON.stringify({ level: 0, weapon: 99 }),
    }));
    expect(response.status).toBe(400);
  });
});
