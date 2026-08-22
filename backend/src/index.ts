import { ROOM_CODE_PATTERN, TOKEN_PATTERN } from "./protocol";

export { Room } from "./room";

const ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const ROOM_CODE_LENGTH = 6;

interface CreateRoomBody {
  level: number;
  weapon: number;
  protocol: number;
}

interface JoinRoomBody {
  weapon: number;
  protocol: number;
}

const ONLINE_WEAPONS = new Set([0, 2, 3, 4]);

function log(level: "info" | "error", message: string, data: Record<string, unknown>): void {
  const entry = JSON.stringify({ level, message, timestamp: new Date().toISOString(), ...data });
  if (level === "error") {
    console.error(entry);
  } else {
    console.log(entry);
  }
}

function randomHex(byteLength: number): string {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function randomRoomCode(): string {
  const bytes = new Uint8Array(ROOM_CODE_LENGTH);
  crypto.getRandomValues(bytes);
  let code = "";
  for (const byte of bytes) {
    code += ROOM_CODE_ALPHABET[byte % ROOM_CODE_ALPHABET.length];
  }
  return code;
}

function randomSeed(): number {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return bytes[0] ?? 0;
}

function allowedOrigins(env: Env): Set<string> {
  return new Set(env.ALLOWED_ORIGINS.split(",").map((origin) => origin.trim()));
}

function requestOriginIsAllowed(request: Request, env: Env): boolean {
  const origin = request.headers.get("Origin");
  return origin === null || allowedOrigins(env).has(origin);
}

function corsHeaders(request: Request, env: Env): Headers {
  const headers = new Headers({
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
  });
  const origin = request.headers.get("Origin");
  if (origin !== null && allowedOrigins(env).has(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Vary", "Origin");
  }
  return headers;
}

function json(
  request: Request,
  env: Env,
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders(request, env),
  });
}

async function readCreateBody(request: Request): Promise<CreateRoomBody | null> {
  const contentLength = Number(request.headers.get("Content-Length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > 1_024) {
    return null;
  }
  let value: unknown;
  try {
    value = await request.json();
  } catch {
    return null;
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)
      || !("level" in value)) {
    return null;
  }
  const level = value.level;
  if (typeof level !== "number" || !Number.isInteger(level) || level < 0 || level > 99) {
    return null;
  }
  const weapon = "weapon" in value ? value.weapon : 0;
  if (typeof weapon !== "number" || !Number.isInteger(weapon) || !ONLINE_WEAPONS.has(weapon)) {
    return null;
  }
  const protocol = "protocol" in value ? value.protocol : 1;
  if (typeof protocol !== "number" || !Number.isInteger(protocol) || protocol < 1 || protocol > 2) {
    return null;
  }
  return { level, weapon, protocol };
}

async function readJoinBody(request: Request): Promise<JoinRoomBody | null> {
  const text = await request.text();
  if (text.trim() === "") {
    return { weapon: 0, protocol: 1 };
  }
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)
      || !("weapon" in value)) {
    return null;
  }
  const weapon = value.weapon;
  const protocol = "protocol" in value ? value.protocol : 1;
  if (typeof weapon !== "number" || !Number.isInteger(weapon) || !ONLINE_WEAPONS.has(weapon)
      || typeof protocol !== "number" || !Number.isInteger(protocol)
      || protocol < 1 || protocol > 2) {
    return null;
  }
  return { weapon, protocol };
}

async function createRoom(request: Request, env: Env): Promise<Response> {
  const body = await readCreateBody(request);
  if (body === null) {
    return json(request, env, { error: "Invalid room settings" }, 400);
  }

  for (let attempt = 0; attempt < 8; attempt += 1) {
    const room = randomRoomCode();
    const token = randomHex(32);
    const seed = randomSeed();
    const stub = env.ROOMS.getByName(room);
    if (await stub.reserve(room, token, body.level, seed, body.weapon, body.protocol)) {
      return json(request, env, {
        room, token, player: 0, level: body.level, weapon: body.weapon,
        protocol: body.protocol,
      }, 201);
    }
  }
  return json(request, env, { error: "Could not allocate a room" }, 503);
}

async function joinRoom(request: Request, env: Env, room: string): Promise<Response> {
  const body = await readJoinBody(request);
  if (body === null) {
    return json(request, env, { error: "Invalid fighter" }, 400);
  }
  const token = randomHex(32);
  const result = await env.ROOMS.getByName(room).join(token, body.weapon, body.protocol);
  if (!result.ok) {
    const status = result.reason === "missing" ? 404 : 409;
    return json(request, env, { error: result.reason === "missing" ? "Room not found" : "Room is full" }, status);
  }
  return json(request, env, {
    room, token, player: 1, weapon: body.weapon, protocol: body.protocol,
  }, 200);
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "OPTIONS") {
    if (!requestOriginIsAllowed(request, env)) {
      return new Response(null, { status: 403 });
    }
    const headers = corsHeaders(request, env);
    headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    headers.set("Access-Control-Allow-Headers", "Content-Type");
    headers.set("Access-Control-Max-Age", "86400");
    return new Response(null, { status: 204, headers });
  }

  if (!requestOriginIsAllowed(request, env)) {
    return json(request, env, { error: "Origin not allowed" }, 403);
  }
  if (request.method === "GET" && url.pathname === "/health") {
    return json(request, env, { ok: true, service: "zawarudo-rooms" });
  }
  if (request.method === "POST" && url.pathname === "/rooms") {
    return createRoom(request, env);
  }

  const match = /^\/rooms\/([^/]+)\/(join|socket)$/.exec(url.pathname);
  if (match === null) {
    return json(request, env, { error: "Not found" }, 404);
  }
  const room = (match[1] ?? "").toUpperCase();
  const action = match[2] ?? "";
  if (!ROOM_CODE_PATTERN.test(room)) {
    return json(request, env, { error: "Invalid room code" }, 400);
  }
  if (action === "join" && request.method === "POST") {
    return joinRoom(request, env, room);
  }
  if (action === "socket" && request.method === "GET") {
    const token = url.searchParams.get("token") ?? "";
    if (!TOKEN_PATTERN.test(token)) {
      return json(request, env, { error: "Invalid room token" }, 401);
    }
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return json(request, env, { error: "Expected WebSocket upgrade" }, 426);
    }
    return env.ROOMS.getByName(room).fetch(request);
  }
  return json(request, env, { error: "Method not allowed" }, 405);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const startedAt = Date.now();
    try {
      const response = await route(request, env);
      log("info", "request_complete", {
        method: request.method,
        path: new URL(request.url).pathname,
        status: response.status,
        durationMs: Date.now() - startedAt,
      });
      return response;
    } catch (error) {
      log("error", "request_failed", {
        method: request.method,
        path: new URL(request.url).pathname,
        error: error instanceof Error ? error.message : String(error),
        durationMs: Date.now() - startedAt,
      });
      return json(request, env, { error: "Internal server error" }, 500);
    }
  },
} satisfies ExportedHandler<Env>;
