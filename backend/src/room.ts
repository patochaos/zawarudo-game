import { DurableObject } from "cloudflare:workers";
import {
  DEFAULT_MATCH_LIVES,
  SELECTION_PROTOCOL,
  SUPPORTED_PROTOCOLS,
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

// A forfeited match has no simulated result to agree on, so the stored report carries a marker
// instead of a digest. Nothing compares it: the room is already game_over when it is written.
const FORFEIT_DIGEST = "forfeit";

// WebSocket close codes the client reads to stop reconnecting to a seat that no longer exists.
export const CLOSE_SEAT_LOST = 4003;
export const CLOSE_ROOM_CLOSED = 4004;
// A seat is only up for grabs after its socket has been gone this long. It covers the gap between
// the join request and the socket opening, and the client's reconnect after a Wi-Fi blip.
export const SEAT_GRACE_MS = 15_000;

type RoomPhase = "waiting" | "selecting" | "planning" | "executing" | "game_over" | "desync";

type RoomRow = {
  code: string;
  phase: RoomPhase;
  level: number;
  seed: number;
  turn: number;
  host_token: string;
  guest_token: string | null;
  capacity: number;
  protocol: number;
  lives: number;
} & Record<string, SqlStorageValue>;

type SelectionRow = {
  slot: number;
  weapon: number;
  level_vote: number;
  lives_vote: number;
  ready: number;
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
  reason?: "missing" | "full" | "rate_limited" | "protocol_mismatch";
  player?: PlayerSlot;
  capacity?: number;
  protocol?: number;
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
  names?: string[];
  capacity?: number;
  protocol?: number;
}

function freshSeed(): number {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return bytes[0] ?? 0;
}

/**
 * The most-voted value. A tie is broken at random among the tied values, so no seat order
 * decides a split table.
 */
export function resolveVote(votes: number[], fallback: number): { value: number; tied: boolean } {
  const counts = new Map<number, number>();
  for (const vote of votes) {
    counts.set(vote, (counts.get(vote) ?? 0) + 1);
  }
  if (counts.size === 0) {
    return { value: fallback, tied: false };
  }
  const top = Math.max(...counts.values());
  const leaders = [...counts.entries()].filter(([, count]) => count === top).map(([value]) => value);
  leaders.sort((a, b) => a - b);
  if (leaders.length === 1) {
    return { value: leaders[0] ?? fallback, tied: false };
  }
  return { value: leaders[freshSeed() % leaders.length] ?? fallback, tied: true };
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
    const migrated = this.ctx.storage.sql.exec<{ id: number }>(
      "SELECT id FROM _sql_schema_migrations WHERE id = 2",
    ).toArray().length > 0;
    if (!migrated) {
      this.ctx.storage.sql.exec(`
        ALTER TABLE room ADD COLUMN capacity INTEGER NOT NULL DEFAULT 2;
        CREATE TABLE participants (slot INTEGER PRIMARY KEY, token TEXT NOT NULL UNIQUE);
        INSERT INTO participants SELECT 0, host_token FROM room;
        INSERT INTO participants SELECT 1, guest_token FROM room WHERE guest_token IS NOT NULL;
        INSERT INTO _sql_schema_migrations (id, applied_at) VALUES (2, unixepoch());
      `);
    }
    const protocolMigrated = this.ctx.storage.sql.exec<{ id: number }>(
      "SELECT id FROM _sql_schema_migrations WHERE id = 3",
    ).toArray().length > 0;
    if (!protocolMigrated) {
      this.ctx.storage.sql.exec(`
        ALTER TABLE room ADD COLUMN protocol INTEGER NOT NULL DEFAULT 2;
        INSERT INTO _sql_schema_migrations (id, applied_at) VALUES (3, unixepoch());
      `);
    }
    const namesMigrated = this.ctx.storage.sql.exec<{ id: number }>(
      "SELECT id FROM _sql_schema_migrations WHERE id = 4",
    ).toArray().length > 0;
    if (!namesMigrated) {
      // Seats created before nicknames existed keep an empty name, which clients show as P1..P4.
      this.ctx.storage.sql.exec(`
        ALTER TABLE participants ADD COLUMN name TEXT NOT NULL DEFAULT '';
        INSERT INTO _sql_schema_migrations (id, applied_at) VALUES (4, unixepoch());
      `);
    }
    const selectionMigrated = this.ctx.storage.sql.exec<{ id: number }>(
      "SELECT id FROM _sql_schema_migrations WHERE id = 5",
    ).toArray().length > 0;
    if (!selectionMigrated) {
      // A level vote of -1 means "no vote yet"; the selection phase seeds it with the room's arena.
      this.ctx.storage.sql.exec(`
        ALTER TABLE room ADD COLUMN lives INTEGER NOT NULL DEFAULT ${DEFAULT_MATCH_LIVES};
        ALTER TABLE fighters ADD COLUMN level_vote INTEGER NOT NULL DEFAULT -1;
        ALTER TABLE fighters ADD COLUMN lives_vote INTEGER NOT NULL DEFAULT ${DEFAULT_MATCH_LIVES};
        ALTER TABLE fighters ADD COLUMN ready INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE participants ADD COLUMN last_seen INTEGER NOT NULL DEFAULT 0;
        INSERT INTO _sql_schema_migrations (id, applied_at) VALUES (5, unixepoch());
      `);
    }
  }

  private room(): RoomRow | null {
    return this.ctx.storage.sql.exec<RoomRow>(
      "SELECT code, phase, level, seed, turn, host_token, guest_token, capacity, protocol, lives FROM room WHERE singleton = 1",
    ).toArray()[0] ?? null;
  }

  async reserve(
    code: string,
    hostToken: string,
    level: number,
    seed: number,
    hostWeapon: number,
    capacity: 2 | 4 = 2,
    protocol: number = SELECTION_PROTOCOL,
    hostName: string = "",
  ): Promise<boolean> {
    if (!SUPPORTED_PROTOCOLS.has(protocol) || (protocol === 2 && capacity !== 2)) {
      return false;
    }
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
      "INSERT OR REPLACE INTO fighters (slot, weapon, level_vote) VALUES (0, ?, ?)",
      hostWeapon, level,
    );
    this.ctx.storage.sql.exec("UPDATE room SET capacity = ?, protocol = ? WHERE singleton = 1", capacity, protocol);
    this.ctx.storage.sql.exec(
      "INSERT INTO participants (slot, token, name) VALUES (0, ?, ?)", hostToken, hostName,
    );
    await this.ctx.storage.setAlarm(Date.now() + ROOM_LIFETIME_MS);
    return true;
  }

  async join(
    guestToken: string,
    guestWeapon: number,
    protocol: number = SELECTION_PROTOCOL,
    guestName: string = "",
  ): Promise<JoinResult> {
    if (!this.allowJoinAttempt()) {
      return { ok: false, reason: "rate_limited" };
    }
    const room = this.room();
    if (room === null) {
      return { ok: false, reason: "missing" };
    }
    if (protocol !== room.protocol) {
      return { ok: false, reason: "protocol_mismatch", protocol: room.protocol };
    }
    const slot = this.openSeat(room);
    if (slot === null) {
      return { ok: false, reason: "full" };
    }
    this.ctx.storage.sql.exec(
      "INSERT INTO participants (slot, token, name, last_seen) VALUES (?, ?, ?, ?)",
      slot, guestToken, guestName, Date.now(),
    );
    if (slot === 1) {
      this.ctx.storage.sql.exec("UPDATE room SET guest_token = ? WHERE singleton = 1", guestToken);
    }
    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO fighters (slot, weapon) VALUES (?, ?)", slot, guestWeapon,
    );
    await this.ctx.storage.setAlarm(Date.now() + ROOM_LIFETIME_MS);
    return { ok: true, player: slot, capacity: room.capacity };
  }

  /**
   * The lowest empty seat. Before the first turn of a protocol 4 room, a guest seat whose socket
   * is gone counts as empty: a player who closed the tab must not lock the room forever. The
   * evicted seat's token stops working, so its owner cannot come back into someone else's seat.
   */
  private openSeat(room: RoomRow): PlayerSlot | null {
    const seats = this.ctx.storage.sql.exec<{ slot: number; last_seen: number }>(
      "SELECT slot, last_seen FROM participants",
    ).toArray();
    const taken = new Set(seats.map((row) => row.slot));
    const lastSeen = new Map(seats.map((row) => [row.slot, Number(row.last_seen)]));
    if (room.phase === "waiting") {
      for (const slot of this.slots(room)) {
        if (!taken.has(slot)) return slot;
      }
    }
    if (room.protocol < SELECTION_PROTOCOL || (room.phase !== "waiting" && room.phase !== "selecting")) {
      return null;
    }
    for (const slot of this.slots(room)) {
      const idle = Date.now() - (lastSeen.get(slot) ?? 0) >= SEAT_GRACE_MS;
      if (slot !== 0 && taken.has(slot) && idle && !this.isConnected(slot)) {
        this.freeSeat(slot, CLOSE_SEAT_LOST);
        if (room.phase === "selecting") {
          this.ctx.storage.sql.exec("UPDATE room SET phase = 'waiting' WHERE singleton = 1");
          this.broadcast({ type: "peer_left", player: slot });
        }
        log("info", "seat_evicted", { room: room.code, slot });
        return slot;
      }
    }
    return null;
  }

  private freeSeat(slot: PlayerSlot, closeCode: number): void {
    this.ctx.storage.sql.exec("DELETE FROM participants WHERE slot = ?", slot);
    this.ctx.storage.sql.exec("DELETE FROM fighters WHERE slot = ?", slot);
    this.ctx.storage.sql.exec("DELETE FROM rematch_ready WHERE slot = ?", slot);
    if (slot === 1) {
      this.ctx.storage.sql.exec("UPDATE room SET guest_token = NULL WHERE singleton = 1");
    }
    for (const socket of this.ctx.getWebSockets(`player:${slot}`)) {
      try {
        socket.close(closeCode, "Seat released");
      } catch {
        // Already closing.
      }
    }
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
      protocol: room.protocol,
      weapons: this.weapons(),
      names: this.names(),
      capacity: room.capacity,
    };
  }

  override async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return Response.json({ error: "Expected WebSocket upgrade" }, { status: 426 });
    }

    const room = this.room();
    const token = new URL(request.url).searchParams.get("token") ?? "";
    const slot = room === null ? undefined : this.ctx.storage.sql.exec<{ slot: PlayerSlot }>(
      "SELECT slot FROM participants WHERE token = ?", token,
    ).toArray()[0]?.slot;
    if (room === null || slot === undefined) {
      // An HTTP error on the upgrade is invisible to a browser WebSocket, which would retry
      // forever. Accept and close with a code the client reads as "this seat is gone".
      const refused = new WebSocketPair();
      refused[1].accept();
      refused[1].close(room === null ? CLOSE_ROOM_CLOSED : CLOSE_SEAT_LOST,
        room === null ? "Room closed" : "Seat released");
      return new Response(null, { status: 101, webSocket: refused[0] });
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

    this.send(server, {
      type: "connected", room: room.code, player: slot, capacity: room.capacity, names: this.names(),
    });
    // Peers already in the room learn the newcomer's name here; room_state only goes to the
    // socket that just connected.
    this.broadcast({ type: "peer_status", player: slot, connected: true, name: this.names()[slot] ?? "" });
    this.sendRoomState(server);
    this.maybeStartMatch();
    await this.maybeStartRematch();
    await this.maybeFinishSelection();
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
        case "forfeit":
          this.receiveForfeit(ws, attachment.slot);
          break;
        case "select":
          await this.receiveSelect(ws, attachment.slot, parsed);
          break;
        case "leave":
          this.receiveLeave(ws, attachment.slot);
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
      this.ctx.storage.sql.exec(
        "UPDATE participants SET last_seen = ? WHERE slot = ?", Date.now(), attachment.slot,
      );
    }
    if (attachment !== null && !this.isConnected(attachment.slot)) {
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
      DELETE FROM participants;
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
    if (rows.length !== room.capacity) {
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
    if (this.slots(room).some((player) => plans[player] === undefined)) {
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
    if (this.rejectMixedResults(turn, "match_reports")) return;
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
    if (rows.length !== room.capacity) {
      this.send(ws, { type: "turn_complete_ack", turn });
      return;
    }
    if (rows.some((row) => row.digest !== rows[0]?.digest)) {
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
    if (this.rejectMixedResults(turn, "turn_results")) return;
    if (winner >= room.capacity) {
      this.sendError(ws, "invalid_winner", "Winner is not in this room");
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
    if (rows.length !== room.capacity) {
      this.send(ws, { type: "match_over_ack", turn });
      return;
    }
    if (rows.some((row) => row.winner !== rows[0]?.winner || row.digest !== rows[0]?.digest)) {
      this.ctx.storage.sql.exec("UPDATE room SET phase = 'desync' WHERE singleton = 1");
      this.broadcast({ type: "desync", turn });
      return;
    }
    this.ctx.storage.sql.exec("UPDATE room SET phase = 'game_over' WHERE singleton = 1");
    this.broadcast({ type: "match_over", turn, winner });
  }

  // A client seeing game over while another sees a continuing turn is also a desync.
  // Without this check each report barrier waits forever for the other report type.
  private rejectMixedResults(turn: number, table: "match_reports" | "turn_results"): boolean {
    const rows = this.ctx.storage.sql.exec<{ slot: number }>(
      `SELECT slot FROM ${table} WHERE turn = ? LIMIT 1`, turn,
    ).toArray();
    if (rows.length === 0) return false;
    this.ctx.storage.sql.exec("UPDATE room SET phase = 'desync' WHERE singleton = 1");
    this.broadcast({ type: "desync", turn });
    return true;
  }

  private receiveForfeit(ws: WebSocket, slot: PlayerSlot): void {
    const room = this.room();
    if (room === null || (room.phase !== "planning" && room.phase !== "executing")) {
      this.sendError(ws, "wrong_phase", "A forfeit can only be claimed during a live match");
      return;
    }
    if (room.capacity > 2) {
      this.sendError(ws, "forfeit_unavailable", "Wait for disconnected players to reconnect or leave the match");
      return;
    }
    // The only anti-abuse gate: the win is granted against a peer that is gone right now, never
    // against one who is still connected. No timer, so the 24h alarm stays the room's only one.
    const peer: PlayerSlot = slot === 0 ? 1 : 0;
    if (this.isConnected(peer)) {
      this.sendError(ws, "peer_present", "The other player is still connected");
      return;
    }
    this.ctx.storage.sql.exec(
      `INSERT OR REPLACE INTO match_reports (turn, slot, winner, digest)
       VALUES (?, ?, ?, ?)`,
      room.turn,
      slot,
      slot,
      FORFEIT_DIGEST,
    );
    this.ctx.storage.sql.exec("UPDATE room SET phase = 'game_over' WHERE singleton = 1");
    log("info", "forfeit_granted", { room: room.code, slot, turn: room.turn });
    this.broadcast({ type: "opponent_left", winner: slot, turn: room.turn });
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
    // Player 1 owns room-level choices in protocol 3 rooms. Protocol 4 votes in the selection
    // phase instead, so every rematch level is ignored there.
    if (slot === 0 && room.protocol < SELECTION_PROTOCOL) {
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
    await this.maybeStartRematch();
  }

  private async maybeStartRematch(): Promise<void> {
    const room = this.room();
    if (room === null || room.phase !== "game_over") return;
    const ready = this.ctx.storage.sql.exec<{ slot: PlayerSlot }>(
      "SELECT slot FROM rematch_ready ORDER BY slot",
    ).toArray();
    if (ready.length !== room.capacity || !this.slots(room).every((player) => this.isConnected(player))) {
      return;
    }
    if (room.protocol >= SELECTION_PROTOCOL) {
      this.ctx.storage.sql.exec("DELETE FROM rematch_ready");
      await this.ctx.storage.setAlarm(Date.now() + ROOM_LIFETIME_MS);
      this.startSelection();
      return;
    }
    const selectedLevel = room.level;
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
      names: this.names(), capacity: room.capacity,
    });
  }

  private maybeStartMatch(): void {
    const room = this.room();
    if (room === null || room.phase !== "waiting") {
      return;
    }
    if (!this.slots(room).every((player) => this.isSeated(player) && this.isConnected(player))) {
      return;
    }
    if (room.protocol >= SELECTION_PROTOCOL) {
      this.startSelection();
      return;
    }
    this.ctx.storage.sql.exec("UPDATE room SET phase = 'planning' WHERE singleton = 1");
    this.broadcast({
      type: "match_start",
      level: room.level,
      seed: room.seed,
      turn: room.turn,
      weapons: this.weapons(),
      names: this.names(),
      capacity: room.capacity,
    });
  }

  /** Every seat is filled and connected: open the fighter and arena picks. Earlier picks stay. */
  private startSelection(): void {
    const room = this.room();
    if (room === null) return;
    this.ctx.storage.sql.exec("UPDATE room SET phase = 'selecting' WHERE singleton = 1");
    this.ctx.storage.sql.exec(
      "UPDATE fighters SET ready = 0, level_vote = CASE WHEN level_vote < 0 THEN ? ELSE level_vote END",
      room.level,
    );
    this.broadcast(this.selectionState());
  }

  private async receiveSelect(
    ws: WebSocket,
    slot: PlayerSlot,
    choice: { weapon: number; level: number; lives: number; ready: boolean },
  ): Promise<void> {
    const room = this.room();
    if (room === null || room.phase !== "selecting") {
      this.sendError(ws, "wrong_phase", "The room is not choosing fighters");
      return;
    }
    this.ctx.storage.sql.exec(
      "UPDATE fighters SET weapon = ?, level_vote = ?, lives_vote = ?, ready = ? WHERE slot = ?",
      choice.weapon, choice.level, choice.lives, choice.ready ? 1 : 0, slot,
    );
    this.broadcast(this.selectionState());
    await this.maybeFinishSelection();
  }

  private async maybeFinishSelection(): Promise<void> {
    const room = this.room();
    if (room === null || room.phase !== "selecting") return;
    const rows = this.selections();
    if (rows.length !== room.capacity || rows.some((row) => Number(row.ready) !== 1)
        || !this.slots(room).every((player) => this.isConnected(player))) {
      return;
    }
    const arena = resolveVote(rows.map((row) => Number(row.level_vote)), room.level);
    const lives = resolveVote(rows.map((row) => Number(row.lives_vote)), DEFAULT_MATCH_LIVES);
    const seed = freshSeed();
    this.ctx.storage.sql.exec(
      "UPDATE room SET phase = 'planning', level = ?, lives = ?, seed = ?, turn = 1 WHERE singleton = 1",
      arena.value, lives.value, seed,
    );
    this.ctx.storage.sql.exec(`
      DELETE FROM plans;
      DELETE FROM turn_results;
      DELETE FROM match_reports;
      DELETE FROM rematch_ready;
    `);
    this.ctx.storage.sql.exec("UPDATE fighters SET ready = 0");
    await this.ctx.storage.setAlarm(Date.now() + ROOM_LIFETIME_MS);
    this.broadcast({
      type: "match_start", level: arena.value, lives: lives.value, seed, turn: 1,
      weapons: this.weapons(), names: this.names(), capacity: room.capacity,
      level_tied: arena.tied, lives_tied: lives.tied,
    });
  }

  /**
   * A deliberate exit. Before and between matches of a protocol 4 room the seat is released so
   * someone else can take it; the host leaving closes the room for everyone. During a match it is
   * an ordinary disconnect, which the forfeit and reconnect rules already cover.
   */
  private receiveLeave(ws: WebSocket, slot: PlayerSlot): void {
    const room = this.room();
    const between = room !== null && room.protocol >= SELECTION_PROTOCOL
      && (room.phase === "waiting" || room.phase === "selecting" || room.phase === "game_over"
        || room.phase === "desync");
    if (room === null || !between) {
      try { ws.close(1000, "Left room"); } catch { /* already closed */ }
      return;
    }
    if (slot === 0) {
      this.closeRoom();
      return;
    }
    this.freeSeat(slot, 1000);
    // Whoever is still here goes back to waiting for a full table: a finished match cannot be
    // rematched with an empty seat, and a desynced one is over anyway.
    this.ctx.storage.sql.exec("UPDATE room SET phase = 'waiting', turn = 1 WHERE singleton = 1");
    this.ctx.storage.sql.exec(`
      DELETE FROM plans;
      DELETE FROM turn_results;
      DELETE FROM match_reports;
      DELETE FROM rematch_ready;
    `);
    log("info", "player_left", { room: room.code, slot });
    this.broadcast({ type: "peer_left", player: slot });
    for (const socket of this.ctx.getWebSockets()) {
      this.sendRoomState(socket);
    }
  }

  private closeRoom(): void {
    this.broadcast({ type: "room_closed" });
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.close(CLOSE_ROOM_CLOSED, "Room closed");
      } catch {
        // Already closing.
      }
    }
    this.ctx.storage.sql.exec(`
      DELETE FROM plans;
      DELETE FROM turn_results;
      DELETE FROM match_reports;
      DELETE FROM rematch_ready;
      DELETE FROM participants;
      DELETE FROM fighters;
      DELETE FROM room;
    `);
  }

  private selections(): SelectionRow[] {
    return this.ctx.storage.sql.exec<SelectionRow>(
      "SELECT slot, weapon, level_vote, lives_vote, ready FROM fighters ORDER BY slot",
    ).toArray();
  }

  private selectionState(): Record<string, unknown> {
    const room = this.room();
    const capacity = room?.capacity ?? 2;
    const levelVotes: number[] = Array(capacity).fill(-1);
    const livesVotes: number[] = Array(capacity).fill(DEFAULT_MATCH_LIVES);
    const ready: boolean[] = Array(capacity).fill(false);
    for (const row of this.selections()) {
      if (row.slot >= 0 && row.slot < capacity) {
        levelVotes[row.slot] = Number(row.level_vote);
        livesVotes[row.slot] = Number(row.lives_vote);
        ready[row.slot] = Number(row.ready) === 1;
      }
    }
    return {
      type: "selection_state",
      phase: room?.phase ?? "waiting",
      weapons: this.weapons(),
      level_votes: levelVotes,
      lives_votes: livesVotes,
      ready,
      names: this.names(),
      connected: room === null ? [] : this.slots(room).map((player) => this.isConnected(player)),
      capacity,
    };
  }

  private sendRoomState(ws: WebSocket): void {
    const room = this.room();
    if (room === null) {
      return;
    }
    const selection = this.selectionState();
    this.send(ws, {
      type: "room_state",
      room: room.code,
      phase: room.phase,
      level: room.level,
      lives: room.lives,
      seed: room.seed,
      turn: room.turn,
      connected: this.slots(room).map((player) => this.isConnected(player)),
      seated: this.slots(room).map((player) => this.isSeated(player)),
      weapons: this.weapons(),
      names: this.names(),
      capacity: room.capacity,
      level_votes: selection.level_votes,
      lives_votes: selection.lives_votes,
      ready: selection.ready,
    });
  }

  /** One entry per seat; an empty string marks a seat without a nickname. */
  private names(): string[] {
    const rows = this.ctx.storage.sql.exec<{ slot: number; name: string }>(
      "SELECT slot, name FROM participants ORDER BY slot",
    ).toArray();
    const names: string[] = Array(this.room()?.capacity ?? 2).fill("");
    for (const row of rows) {
      if (row.slot >= 0 && row.slot < names.length) {
        names[row.slot] = String(row.name ?? "");
      }
    }
    return names;
  }

  private weapons(): number[] {
    const rows = this.ctx.storage.sql.exec<{ slot: number; weapon: number }>(
      "SELECT slot, weapon FROM fighters ORDER BY slot",
    ).toArray();
    const weapons: number[] = Array(this.room()?.capacity ?? 2).fill(0);
    for (const row of rows) {
      if (row.slot >= 0 && row.slot < weapons.length) {
        weapons[row.slot] = Number(row.weapon);
      }
    }
    return weapons;
  }

  private slots(room: RoomRow): PlayerSlot[] {
    return Array.from({ length: room.capacity }, (_, slot) => slot as PlayerSlot);
  }

  private isSeated(slot: PlayerSlot): boolean {
    return this.ctx.storage.sql.exec<{ slot: number }>(
      "SELECT slot FROM participants WHERE slot = ?", slot,
    ).toArray().length > 0;
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
