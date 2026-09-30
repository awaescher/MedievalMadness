// Medieval Madness relay on Cloudflare Workers + Durable Objects (free plan, nothing to operate).
// Same protocol as tools/relay_server.gd: JSON text frames, rooms with a 4 letter code, star topology.
//   GET /host           (WebSocket)  -> opens a new room, the first frame answers with the code
//   GET /room/<CODE>    (WebSocket)  -> joins a room
// Client -> relay: {"t":"hi","role":"host|join","name":"..","ver":".."}, {"t":"msg","to":<id>,"d":{...}}
// Relay -> client: {"t":"hello","id":..,"code":..,"host":..,"roster":{..}}, {"t":"peer","id":..,"name":..,"on":bool},
//                  {"t":"msg","from":<id>,"d":{...}}, {"t":"err","m":".."}

const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const MAX_PEERS = 8;

function newCode() {
  let c = "";
  const r = new Uint8Array(4);
  crypto.getRandomValues(r);
  for (let i = 0; i < 4; i++) c += ALPHABET[r[i] % ALPHABET.length];
  return c;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Medieval Madness relay: connect with a WebSocket.", { status: 200 });
    }
    if (url.pathname === "/host") {
      for (let attempt = 0; attempt < 8; attempt++) {
        const code = newCode();
        const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
        const res = await stub.fetch(new Request("https://room/?role=host&code=" + code, request));
        if (res.status !== 409) return res;
      }
      return new Response("no free room code", { status: 503 });
    }
    const m = url.pathname.match(/^\/room\/([A-Za-z0-9]{4})$/);
    if (m) {
      const code = m[1].toUpperCase();
      const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
      return stub.fetch(new Request("https://room/?role=join&code=" + code, request));
    }
    return new Response("not found", { status: 404 });
  },
};

export class Room {
  constructor(state, env) {
    this.peers = new Map(); // WebSocket -> {id, name}
    this.next = 2;
    this.hostWs = null;
    this.code = null;
  }

  send(ws, obj) {
    try { ws.send(JSON.stringify(obj)); } catch (e) { /* closed */ }
  }

  roster() {
    const out = {};
    for (const p of this.peers.values()) out[String(p.id)] = p.name;
    return out;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const role = url.searchParams.get("role");
    const code = url.searchParams.get("code");
    if (role === "host" && this.hostWs) return new Response("taken", { status: 409 });
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.accept();
    let joined = false;
    server.addEventListener("message", (ev) => {
      let m;
      try { m = JSON.parse(ev.data); } catch (e) { return; }
      if (!joined) {
        if (m.t !== "hi") return;
        const name = String(m.name || "?").slice(0, 24);
        if (role === "host") {
          this.hostWs = server;
          this.code = code;
          this.peers.set(server, { id: 1, name });
          this.send(server, { t: "hello", id: 1, code, host: true, roster: this.roster() });
        } else {
          if (!this.hostWs) { this.send(server, { t: "err", m: "room_not_found" }); server.close(1000, "room_not_found"); return; }
          if (this.peers.size >= MAX_PEERS) { this.send(server, { t: "err", m: "room_full" }); server.close(1000, "room_full"); return; }
          const id = this.next++;
          this.peers.set(server, { id, name });
          this.send(server, { t: "hello", id, code, host: false, roster: this.roster() });
          for (const [ws, p] of this.peers) if (ws !== server) this.send(ws, { t: "peer", id, name, on: true });
        }
        joined = true;
        return;
      }
      if (m.t !== "msg") return;
      const me = this.peers.get(server);
      if (!me) return;
      const out = { t: "msg", from: me.id, d: m.d };
      let to = me.id === 1 ? Number(m.to ?? 1) : 1;
      if (to === 0) {
        for (const [ws, p] of this.peers) if (ws !== server) this.send(ws, out);
      } else {
        for (const [ws, p] of this.peers) if (p.id === to) this.send(ws, out);
      }
    });
    const leave = () => {
      const me = this.peers.get(server);
      if (!me) return;
      this.peers.delete(server);
      if (me.id === 1) {
        for (const [ws] of this.peers) { this.send(ws, { t: "err", m: "host_left" }); try { ws.close(1000, "host_left"); } catch (e) {} }
        this.peers.clear();
        this.hostWs = null;
      } else {
        for (const [ws] of this.peers) this.send(ws, { t: "peer", id: me.id, name: me.name, on: false });
      }
    };
    server.addEventListener("close", leave);
    server.addEventListener("error", leave);
    return new Response(null, { status: 101, webSocket: client });
  }
}
