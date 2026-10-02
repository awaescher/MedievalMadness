// Minimal Medieval Madness relay for Node.js (>= 18) - a TEMPLATE to start from. Speaks protocol v1 (see ../PROTOCOL.md).
//   npm install && node relay_node.mjs               (port 9080, or PORT=1234 node relay_node.mjs)
// Players then enter  ws://<this machine>:9080  under "Own relay server" in the game (put a TLS proxy in front for wss://).
// It keeps no game state: it only hands "d" payloads from one peer to another. Rooms live in memory.
import { WebSocketServer } from "ws";
import http from "node:http";

const PORT = Number(process.env.PORT || 9080);
const RELAY_PROTO = 1;
const MAX_PEERS = 8;
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0 O 1 I

const rooms = new Map(); // code -> { peers: Map<ws, {id, name}>, next: number }

const newCode = () => {
  for (;;) {
    let c = "";
    for (let i = 0; i < 4; i++) c += ALPHABET[Math.floor(Math.random() * ALPHABET.length)];
    if (!rooms.has(c)) return c;
  }
};
const send = (ws, obj) => { try { ws.send(JSON.stringify(obj)); } catch { /* closed */ } };
const roster = (room) => Object.fromEntries([...room.peers.values()].map((p) => [String(p.id), p.name]));

// plain HTTP GET answers like the Cloudflare worker, handy to check the deployment in a browser
const server = http.createServer((req, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({ service: "medieval-madness-relay", proto: RELAY_PROTO }));
});
const wss = new WebSocketServer({ noServer: true });

server.on("upgrade", (req, socket, head) => {
  const path = new URL(req.url, "http://x").pathname;
  let role = null, code = null;
  if (path === "/v1/host") { role = "host"; code = newCode(); }
  else {
    const m = path.match(/^\/v1\/room\/([A-Za-z0-9]{4})$/);
    if (m) { role = "join"; code = m[1].toUpperCase(); }
  }
  if (!role) { socket.destroy(); return; }
  wss.handleUpgrade(req, socket, head, (ws) => onConnection(ws, role, code));
});

function onConnection(ws, role, code) {
  let me = null, room = null;
  ws.on("message", (raw) => {
    let m; try { m = JSON.parse(raw.toString()); } catch { return; }
    if (!me) {                                   // the first frame must be "hi"
      if (m.t !== "hi") return;
      const name = String(m.name ?? "?").slice(0, 24);
      if (role === "host") {
        room = { peers: new Map(), next: 2 };
        rooms.set(code, room);
        me = { id: 1, name };
        room.peers.set(ws, me);
        send(ws, { t: "hello", id: 1, code, host: true, relay: RELAY_PROTO, roster: roster(room) });
      } else {
        room = rooms.get(code);
        if (!room) { send(ws, { t: "err", m: "room_not_found" }); ws.close(1000, "room_not_found"); return; }
        if (room.peers.size >= MAX_PEERS) { send(ws, { t: "err", m: "room_full" }); ws.close(1000, "room_full"); return; }
        me = { id: room.next++, name };
        room.peers.set(ws, me);
        send(ws, { t: "hello", id: me.id, code, host: false, relay: RELAY_PROTO, roster: roster(room) });
        for (const [other] of room.peers) if (other !== ws) send(other, { t: "peer", id: me.id, name, on: true });
      }
      return;
    }
    if (m.t !== "msg") return;                   // {"t":"ping"} and everything else is ignored
    const out = { t: "msg", from: me.id, d: m.d };
    const to = me.id === 1 ? Number(m.to ?? 1) : 1; // guests can only talk to the host (star topology)
    for (const [other, p] of room.peers) {
      if (to === 0 ? other !== ws : p.id === to) send(other, out);
    }
  });
  const leave = () => {
    if (!me || !room?.peers.has(ws)) return;
    room.peers.delete(ws);
    if (me.id === 1) {                           // host gone: the room is over for everybody
      for (const [other] of room.peers) { send(other, { t: "err", m: "host_left" }); other.close(1000, "host_left"); }
      rooms.delete(code);
    } else {
      for (const [other] of room.peers) send(other, { t: "peer", id: me.id, name: me.name, on: false });
    }
  };
  ws.on("close", leave);
  ws.on("error", leave);
}

server.listen(PORT, () => console.log(`medieval-madness relay (proto ${RELAY_PROTO}) on :${PORT}`));
