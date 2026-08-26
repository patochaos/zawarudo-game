import { exports } from "cloudflare:workers";
import type { PlayerPlanPayload } from "../src/protocol";
import { PROTOCOL_VERSION } from "../src/protocol";

export const ORIGIN = "https://zawarudo-pi.vercel.app";

export interface ServerMessage extends Record<string, unknown> {
  type: string;
}

export interface CreatedRoom {
  room: string;
  token: string;
}

export function plan(overrides: Partial<PlayerPlanPayload> = {}): PlayerPlanPayload {
  return {
    dirs: [0, 1, 2],
    jumps: [0, 0, 1],
    holds: [1, 1, 0],
    drops: [0, 0, 0],
    shot_tick: 2,
    aim_angle: 30,
    power: 0.5,
    attack_mode: 0,
    super_shot: false,
    ...overrides,
  };
}

export function digest(marker: string): string {
  return marker.repeat(64).slice(0, 64);
}

export async function post(path: string, body: Record<string, unknown>): Promise<Response> {
  return exports.default.fetch(new Request(`https://example.test${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: ORIGIN },
    body: JSON.stringify(body),
  }));
}

export async function createRoom(level = 1, weapon = 0): Promise<CreatedRoom> {
  const response = await post("/rooms", { level, weapon, protocol: PROTOCOL_VERSION });
  if (response.status !== 201) {
    throw new Error(`create failed: ${response.status} ${await response.text()}`);
  }
  return response.json<CreatedRoom>();
}

export async function joinRoom(room: string, weapon = 0): Promise<string> {
  const response = await post(`/rooms/${room}/join`, { weapon, protocol: PROTOCOL_VERSION });
  if (response.status !== 200) {
    throw new Error(`join failed: ${response.status} ${await response.text()}`);
  }
  return (await response.json<{ token: string }>()).token;
}

async function tick(milliseconds: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}

/** Lets every message the server has already queued reach the client before we assert. */
export async function settle(): Promise<void> {
  await tick(40);
}

export class TestSocket {
  readonly received: ServerMessage[] = [];
  closeCode = -1;

  private constructor(private readonly ws: WebSocket) {}

  static async open(room: string, token: string): Promise<TestSocket> {
    const response = await exports.default.fetch(new Request(
      `https://example.test/rooms/${room}/socket?token=${token}`,
      { headers: { Upgrade: "websocket", Origin: ORIGIN } },
    ));
    const ws = response.webSocket;
    if (response.status !== 101 || ws === null) {
      throw new Error(`socket upgrade failed: ${response.status} ${await response.text()}`);
    }
    const socket = new TestSocket(ws);
    ws.accept();
    ws.addEventListener("message", (event: MessageEvent) => {
      if (typeof event.data === "string") {
        socket.received.push(JSON.parse(event.data) as ServerMessage);
      }
    });
    ws.addEventListener("close", (event: CloseEvent) => {
      socket.closeCode = event.code;
    });
    return socket;
  }

  send(payload: Record<string, unknown>): void {
    this.ws.send(JSON.stringify(payload));
  }

  sendPlan(turn: number, overrides: Partial<PlayerPlanPayload> = {}): void {
    this.send({ type: "plan", turn, plan: plan(overrides) });
  }

  /** Waits for the first message of `type`, removing it from the buffer. */
  async waitFor(type: string, timeoutMs = 2_000): Promise<ServerMessage> {
    return this.waitWhere((message) => message.type === type, `"${type}"`, timeoutMs);
  }

  async waitForError(code: string, timeoutMs = 2_000): Promise<ServerMessage> {
    return this.waitWhere(
      (message) => message.type === "error" && message.code === code,
      `error "${code}"`,
      timeoutMs,
    );
  }

  private async waitWhere(
    predicate: (message: ServerMessage) => boolean,
    label: string,
    timeoutMs: number,
  ): Promise<ServerMessage> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const index = this.received.findIndex(predicate);
      if (index >= 0) {
        return this.received.splice(index, 1)[0] as ServerMessage;
      }
      if (Date.now() >= deadline) {
        throw new Error(`timed out waiting for ${label}; received ${JSON.stringify(this.received)}`);
      }
      await tick(5);
    }
  }

  async waitForClose(timeoutMs = 2_000): Promise<number> {
    const deadline = Date.now() + timeoutMs;
    while (this.closeCode < 0 && Date.now() < deadline) {
      await tick(5);
    }
    return this.closeCode;
  }

  types(): string[] {
    return this.received.map((message) => message.type);
  }

  drain(): void {
    this.received.length = 0;
  }

  close(): void {
    try {
      this.ws.close(1000, "test over");
    } catch {
      // Already closed by the server; nothing to do.
    }
  }
}

export interface MatchFixture {
  room: string;
  hostToken: string;
  guestToken: string;
  host: TestSocket;
  guest: TestSocket;
  seed: number;
  level: number;
}

/** Creates a room, joins it, connects both sockets and waits for the match to start. */
export async function startMatch(
  level = 1,
  weapons: [number, number] = [0, 0],
): Promise<MatchFixture> {
  const created = await createRoom(level, weapons[0]);
  const guestToken = await joinRoom(created.room, weapons[1]);
  const host = await TestSocket.open(created.room, created.token);
  const guest = await TestSocket.open(created.room, guestToken);
  const start = await host.waitFor("match_start");
  await guest.waitFor("match_start");
  host.drain();
  guest.drain();
  return {
    room: created.room,
    hostToken: created.token,
    guestToken,
    host,
    guest,
    seed: start.seed as number,
    level: start.level as number,
  };
}

/** Plays one full turn to completion so a test can reach a later phase. */
export async function playTurn(fixture: MatchFixture, turn: number): Promise<void> {
  fixture.host.sendPlan(turn);
  fixture.guest.sendPlan(turn);
  await fixture.host.waitFor("turn_plans");
  await fixture.guest.waitFor("turn_plans");
  fixture.host.send({ type: "turn_complete", turn, digest: digest("a") });
  fixture.guest.send({ type: "turn_complete", turn, digest: digest("a") });
  await fixture.host.waitFor("turn_start");
  await fixture.guest.waitFor("turn_start");
}
