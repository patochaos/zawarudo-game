import { DurableObject } from "cloudflare:workers";
import {
  parseClientMessage,
  parseConnectionAttachment,
  parsePlan,
  type ConnectionAttachment,
  type PlayerPlanPayload,
  type PlayerSlot,
} from "./protocol";

const ROOM_LIFETIME_MS = 24 * 60 * 60 * 1_000;

// Rate limits. A healthy client sends two messages per turn (plan, turn_complete), so twenty per
// second per socket is far above real play while still capping a flooding peer. Join attempts are
// bounded per room code so a leaked code cannot be hammered.
const MESSAGE_WINDOW_MS = 1_000;
const MAX_MESSAGES_PER_WINDOW = 20;
const JOIN_WINDOW_MS = 60_000;
const MAX_JOIN_ATTEMPTS_PER_WINDOW = 10;

type RoomPhase = "waiting" | "planning" | "executing" | "game_over" | "desync";

type RoomRow = {
  code: string;
  phase: RoomPhase;
  level: number;
  seed: number;
  turn: number;
  host_token: string;
  guest_token: string | null;
} & Record<string, SqlStorageValue>;

type StoredPlanRow = {
  slot: PlayerSlot;
  plan_json: string;
} & Record<string, SqlStorageValue>;

type StoredResultRow = {
  slot: PlayerSlot;
  digest: string;
} & Record<string, SqlStorageValue>;

type StoredMatchReportRow = StoredResultRow & {
  winner: PlayerSlot;
};

export interface JoinResult {
  ok: boolean;
  reason?: "missing" | "full" | "rate_limited";
  player?: PlayerSlot;
}

interface RateWindow {
  startedAt: number;
  count: number;
}

export interface RoomInfo {
  exists: boolean;
  phase?: RoomPhase;
  level?: number;
  seed?: number;
  turn?: number;
  hasGuest?: boolean;
  weapons?: number[];
}

function freshSeed(): number {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return bytes[0] ?? 0;
}

function log(level: "info" | "warn" | "error", message: string, data: Record<string, unknown>): void {
  const entry = JSON.stringify({ level, message, timestamp: new Date().toISOString(), ...data });
  if (level === "error") {
    console.error(entry);
  } else if (level === "warn") {
    console.warn(entry);
  } else {
    console.log(entry);
  }
}

export class Room extends DurableObject<Env> {
  // In-memory only: both windows reset when the object is evicted, which is fine for a throttle.
  private readonly messageRates = new Map<WebSocket, RateWindow>();
  private joinRate: RateWindow = { startedAt: 0, count: 0 };

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      this.migrate();
    });
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  private migrate(): void {
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS _sql_schema_migrations (
        id INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS room (
        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
        code TEXT NOT NULL UNIQUE,
        phase TEXT NOT NULL,
        level INTEGER NOT NULL,
        seed INTEGER NOT NULL,
        turn INTEGER NOT NULL,
        host_token TEXT NOT NULL,
        guest_token TEXT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS plans (
        turn INTEGER NOT NULL,
        slot INTEGER NOT NULL,
        plan_json TEXT NOT NULL,
        PRIMARY KEY (turn, slot)
      );
      CREATE TABLE IF NOT EXISTS turn_results (
        turn INTEGER NOT NULL,
        slot INTEGER NOT NULL,
        digest TEXT NOT NULL,
        PRIMARY KEY (turn, slot)
      );
      CREATE TABLE IF NOT EXISTS match_reports (
        turn INTEGER NOT NULL,
        slot INTEGER NOT NULL,
        winner INTEGER NOT NULL,
        digest TEXT NOT NULL,
        PRIMARY KEY (turn, slot)
      );
      CREATE TABLE IF NOT EXISTS rematch_ready (
        slot INTEGER PRIMARY KEY
      );
      CREATE TABLE IF NOT EXISTS fighters (
        slot INTEGER PRIMARY KEY,
        weapon INTEGER NOT NULL,
        protocol INTEGER NOT NULL DEFAULT 1
      );
      INSERT OR IGNORE INTO _sql_schema_migrations (id, applied_at)
      VALUES (1, unixepoch());
    `);
  }

  private room(): RoomRow | null {
    return this.ctx.storage.sql.exec<RoomRow>(
      "SELECT code, phase, level, seed, turn, host_token, guest_token FROM room WHERE singleton = 1",
    ).toArray()[0] ?? null;
  }

  async reserve(
    code: string,
    hostToken: string,
    level: number,
    seed: number,
    hostWeapon: number,
  ): Promise<boolean> {
    if (this.room() !== null) {
      return false;
    }
    this.ctx.storage.sql.exec(
      `INSERT INTO room
        (singleton, code, phase, level, seed, turn, host_token, guest_token, created_at)
       VALUES (1, ?, 'waiting', ?, ?, 1, ?, NULL, ?)`,
      code,
      level,
      seed,
      hostToken,
      Date.now(),
    );
    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO fighters (slot, weapon) VALUES (0, ?)",
      hostWeapon,
    );
    await this.ctx.storage.setAlarm(Date.now() + ROOM_LIFETIME_MS);
    return true;
  }

  async join(guestToken: string, guestWeapon: number): Promise<JoinResult> {
    if (!this.allowJoinAttempt()) {
      return { ok: false, reason: "rate_limited" };
    }
    const room = this.room();
    if (room === null) {
      return { ok: false, reason: "missing" };
    }
    if (room.guest_token !== null) {
      return { ok: false, reason: "full" };
    }
    this.ctx.storage.sql.exec(
      "UPDATE room SET guest_token = ? WHERE singleton = 1",
      guestToken,
    );
    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO fighters (slot, weapon) VALUES (1, ?)",
      guestWeapon,
    );
    await this.ctx.storage.setAlarm(Date.now() + ROOM_LIFETIME_MS);
    return { ok: true, player: 1 };
  }

  private allowJoinAttempt(): boolean {
    const now = Date.now();
    if (now - this.joinRate.startedAt >= JOIN_WINDOW_MS) {
      this.joinRate = { startedAt: now, count: 1 };
      return true;
    }
    this.joinRate.count += 1;
    if (this.joinRate.count > MAX_JOIN_ATTEMPTS_PER_WINDOW) {
      log("warn", "join_rate_limited", { attempts: this.joinRate.count });
      return false;
    }
    return true;
  }

  getInfo(): RoomInfo {
    const room = this.room();
    if (room === null) {
      return { exists: false };
    }
    return {
      exists: true,
      phase: room.phase,
      level: room.level,
      seed: room.seed,
      turn: room.turn,
      hasGuest: room.guest_token !== null,
      weapons: this.weapons(),
    };
  }

  override async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return Response.json({ error: "Expected WebSocket upgrade" }, { status: 426 });
    }

    const room = this.room();
    if (room === null) {
      return Response.json({ error: "Room not found" }, { status: 404 });
    }
    const token = new URL(request.url).searchParams.get("token") ?? "";
    const slot = token === room.host_token ? 0 : token === room.guest_token ? 1 : -1;
    if (slot !== 0 && slot !== 1) {
      return Response.json({ error: "Invalid room token" }, { status: 401 });
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    for (const existing of this.ctx.getWebSockets(`player:${slot}`)) {
      existing.close(4001, "Reconnected from another socket");
    }

    const attachment: ConnectionAttachment = { slot };
    server.serializeAttachment(attachment);
    this.ctx.acceptWebSocket(server, [`player:${slot}`]);
    await this.ctx.storage.setAlarm(Date.now() + ROOM_LIFETIME_MS);

    this.send(server, { type: "connected", room: room.code, player: slot });
    this.broadcast({ type: "peer_status", player: slot, connected: true });
    this.sendRoomState(server);
    this.maybeStartMatch();
    this.maybeBroadcastStoredPlans();

    return new Response(null, { status: 101, webSocket: client });
  }

  override async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (!this.allowMessage(ws)) {
      return;
    }
    if (typeof message !== "string") {
      this.sendError(ws, "binary_not_supported", "Only text messages are supported");
      return;
    }
    const attachment = parseConnectionAttachment(ws.deserializeAttachment());
    const parsed = parseClientMessage(message);
    if (attachment === null || parsed === null) {
      this.sendError(ws, "invalid_message", "Invalid message payload");
      return;
    }

    try {
      switch (parsed.type) {
        case "plan":
          this.receivePlan(ws, attachment.slot, parsed.turn, parsed.plan);
          break;
        case "turn_complete":
          await this.receiveTurnComplete(ws, attachment.slot, parsed.turn, parsed.digest);
          break;
        case "match_over":
          this.receiveMatchOver(
            ws,
            attachment.slot,
            parsed.turn,
            parsed.winner,
            parsed.digest,
          );
          break;
        case "rematch":
          await this.receiveRematch(ws, attachment.slot, parsed.level);
          break;
      }
    } catch (error) {
      log("error", "websocket_message_failed", {
        error: error instanceof Error ? error.message : String(error),
        slot: attachment.slot,
      });
      this.sendError(ws, "server_error", "Room operation failed");
    }
  }

  private allowMessage(ws: WebSocket): boolean {
    const now = Date.now();
    const window = this.messageRates.get(ws);
    if (window === undefined || now - window.startedAt >= MESSAGE_WINDOW_MS) {
      this.messageRates.set(ws, { startedAt: now, count: 1 });
      return true;
    }
    window.count += 1;
    if (window.count <= MAX_MESSAGES_PER_WINDOW) {
      return true;
    }
    // Warn once per window, then drop silently so the flood cannot amplify into replies.
    if (window.count === MAX_MESSAGES_PER_WINDOW + 1) {
      const attachment = parseConnectionAttachment(ws.deserializeAttachment());
      log("warn", "message_rate_limited", { slot: attachment?.slot ?? -1, count: window.count });
      this.sendError(ws, "rate_limited", "Too many messages, slow down");
    }
    return false;
  }

  override webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean): void {
    this.messageRates.delete(ws);
    const attachment = parseConnectionAttachment(ws.deserializeAttachment());
    if (attachment !== null) {
      this.broadcast({
        type: "peer_status",
        player: attachment.slot,
        connected: false,
      }, ws);
      log("info", "player_disconnected", {
        slot: attachment.slot,
        code,
        reason,
        wasClean,
      });
    }
  }

  override webSocketError(ws: WebSocket, error: unknown): void {
    const attachment = parseConnectionAttachment(ws.deserializeAttachment());
    log("warn", "websocket_error", {
      slot: attachment?.slot ?? -1,
      error: error instanceof Error ? error.message : String(error),
    });
  }

  override async alarm(): Promise<void> {
    if (this.ctx.getWebSockets().length > 0) {
      await this.ctx.storage.setAlarm(Date.now() + ROOM_LIFETIME_MS);
      return;
    }
    this.ctx.storage.sql.exec(`
      DELETE FROM plans;
      DELETE FROM turn_results;
      DELETE FROM match_reports;
      DELETE FROM rematch_ready;
      DELETE FROM fighters;
      DELETE FROM room;
    `);
  }

  private receivePlan(
    ws: WebSocket,
    slot: PlayerSlot,
    turn: number,
    plan: PlayerPlanPayload,
  ): void {
    const room = this.room();
    if (room === null || room.phase !== "planning" || room.turn !== turn) {
      this.sendError(ws, "wrong_phase", "The room is not accepting this plan");
      return;
    }
    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO plans (turn, slot, plan_json) VALUES (?, ?, ?)",
      turn,
      slot,
      JSON.stringify(plan),
    );
    this.send(ws, { type: "plan_ack", turn });
    this.maybeBroadcastStoredPlans();
  }

  private maybeBroadcastStoredPlans(): void {
    const room = this.room();
    if (room === null || (room.phase !== "planning" && room.phase !== "executing")) {
      return;
    }
    const rows = this.ctx.storage.sql.exec<StoredPlanRow>(
      "SELECT slot, plan_json FROM plans WHERE turn = ? ORDER BY slot",
      room.turn,
    ).toArray();
    if (rows.length !== 2) {
      return;
    }

    const plans: PlayerPlanPayload[] = [];
    for (const row of rows) {
      let decoded: unknown;
      try {
        decoded = JSON.parse(row.plan_json);
      } catch {
        return;
      }
      const plan = parsePlan(decoded);
      if (plan === null) {
        return;
      }
      plans[row.slot] = plan;
    }
    if (plans[0] === undefined || plans[1] === undefined) {
      return;
    }
    if (room.phase === "planning") {
      this.ctx.storage.sql.exec(
        "UPDATE room SET phase = 'executing' WHERE singleton = 1",
      );
    }
    this.broadcast({ type: "turn_plans", turn: room.turn, plans });
  }

  private async receiveTurnComplete(
    ws: WebSocket,
    slot: PlayerSlot,
    turn: number,
    digest: string,
  ): Promise<void> {
    const room = this.room();
    if (room === null || room.phase !== "executing" || room.turn !== turn) {
      this.sendError(ws, "wrong_phase", "The room is not accepting this turn result");
      return;
    }
    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO turn_results (turn, slot, digest) VALUES (?, ?, ?)",
      turn,
      slot,
      digest,
    );
    const rows = this.ctx.storage.sql.exec<StoredResultRow>(
      "SELECT slot, digest FROM turn_results WHERE turn = ? ORDER BY slot",
      turn,
    ).toArray();
    if (rows.length !== 2) {
      this.send(ws, { type: "turn_complete_ack", turn });
      return;
    }
    if (rows[0]?.digest !== rows[1]?.digest) {
      this.ctx.storage.sql.exec("UPDATE room SET phase = 'desync' WHERE singleton = 1");
      this.broadcast({ type: "desync", turn });
      return;
    }

    const nextTurn = turn + 1;
    this.ctx.storage.sql.exec(
      "UPDATE room SET turn = ?, phase = 'planning' WHERE singleton = 1",
      nextTurn,
    );
    this.ctx.storage.sql.exec("DELETE FROM plans WHERE turn < ?", nextTurn - 1);
    this.ctx.storage.sql.exec("DELETE FROM turn_results WHERE turn < ?", nextTurn - 1);
    await this.ctx.storage.setAlarm(Date.now() + ROOM_LIFETIME_MS);
    this.broadcast({ type: "turn_start", turn: nextTurn });
  }

  private receiveMatchOver(
    ws: WebSocket,
    slot: PlayerSlot,
    turn: number,
    winner: PlayerSlot,
    digest: string,
  ): void {
    const room = this.room();
    if (room === null || room.phase !== "executing" || room.turn !== turn) {
      this.sendError(ws, "wrong_phase", "The room is not accepting a match result");
      return;
    }
    this.ctx.storage.sql.exec(
      `INSERT OR REPLACE INTO match_reports (turn, slot, winner, digest)
       VALUES (?, ?, ?, ?)`,
      turn,
      slot,
      winner,
      digest,
    );
    const rows = this.ctx.storage.sql.exec<StoredMatchReportRow>(
      "SELECT slot, winner, digest FROM match_reports WHERE turn = ? ORDER BY slot",
      turn,
    ).toArray();
    if (rows.length !== 2) {
      this.send(ws, { type: "match_over_ack", turn });
      return;
    }
    if (rows[0]?.winner !== rows[1]?.winner || rows[0]?.digest !== rows[1]?.digest) {
      this.ctx.storage.sql.exec("UPDATE room SET phase = 'desync' WHERE singleton = 1");
      this.broadcast({ type: "desync", turn });
      return;
    }
    this.ctx.storage.sql.exec("UPDATE room SET phase = 'game_over' WHERE singleton = 1");
    this.broadcast({ type: "match_over", turn, winner });
  }

  private async receiveRematch(
    ws: WebSocket,
    slot: PlayerSlot,
    requestedLevel: number,
  ): Promise<void> {
    const room = this.room();
    if (room === null || room.phase !== "game_over") {
      this.sendError(ws, "wrong_phase", "Rematch is only available after game over");
      return;
    }
    // Player 1 owns room-level choices, just as they did when creating the room.
    // Slot 1 still sends a level; it is ignored.
    if (slot === 0) {
      this.ctx.storage.sql.exec("UPDATE room SET level = ? WHERE singleton = 1", requestedLevel);
    }
    this.ctx.storage.sql.exec("INSERT OR IGNORE INTO rematch_ready (slot) VALUES (?)", slot);
    const ready = this.ctx.storage.sql.exec<{ slot: PlayerSlot }>(
      "SELECT slot FROM rematch_ready ORDER BY slot",
    ).toArray();
    const selectedLevel = this.room()?.level ?? room.level;
    this.broadcast({
      type: "rematch_status",
      ready: ready.map((row) => row.slot),
      level: selectedLevel,
    });
    if (ready.length !== 2) {
      return;
    }

    const seed = freshSeed();
    this.ctx.storage.sql.exec(
      "UPDATE room SET phase = 'planning', seed = ?, turn = 1 WHERE singleton = 1",
      seed,
    );
    this.ctx.storage.sql.exec(`
      DELETE FROM plans;
      DELETE FROM turn_results;
      DELETE FROM match_reports;
      DELETE FROM rematch_ready;
    `);
    await this.ctx.storage.setAlarm(Date.now() + ROOM_LIFETIME_MS);
    this.broadcast({
      type: "match_start", level: selectedLevel, seed, turn: 1, weapons: this.weapons(),
    });
  }

  private maybeStartMatch(): void {
    const room = this.room();
    if (room === null || room.phase !== "waiting" || room.guest_token === null) {
      return;
    }
    if (!this.isConnected(0) || !this.isConnected(1)) {
      return;
    }
    this.ctx.storage.sql.exec("UPDATE room SET phase = 'planning' WHERE singleton = 1");
    this.broadcast({
      type: "match_start",
      level: room.level,
      seed: room.seed,
      turn: room.turn,
      weapons: this.weapons(),
    });
  }

  private sendRoomState(ws: WebSocket): void {
    const room = this.room();
    if (room === null) {
      return;
    }
    this.send(ws, {
      type: "room_state",
      room: room.code,
      phase: room.phase,
      level: room.level,
      seed: room.seed,
      turn: room.turn,
      connected: [this.isConnected(0), this.isConnected(1)],
      weapons: this.weapons(),
    });
  }

  private weapons(): number[] {
    const rows = this.ctx.storage.sql.exec<{ slot: number; weapon: number }>(
      "SELECT slot, weapon FROM fighters ORDER BY slot",
    ).toArray();
    const weapons = [0, 0];
    for (const row of rows) {
      if (row.slot === 0 || row.slot === 1) {
        weapons[row.slot] = Number(row.weapon);
      }
    }
    return weapons;
  }

  private isConnected(slot: PlayerSlot): boolean {
    return this.ctx.getWebSockets(`player:${slot}`).some(
      (ws) => ws.readyState === WebSocket.OPEN,
    );
  }

  private broadcast(payload: Record<string, unknown>, except?: WebSocket): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (socket !== except) {
        this.send(socket, payload);
      }
    }
  }

  private send(ws: WebSocket, payload: Record<string, unknown>): void {
    if (ws.readyState !== WebSocket.OPEN) {
      return;
    }
    try {
      ws.send(JSON.stringify(payload));
    } catch (error) {
      log("warn", "websocket_send_failed", {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }

  private sendError(ws: WebSocket, code: string, message: string): void {
    this.send(ws, { type: "error", code, message });
  }
}
