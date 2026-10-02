// Conformance check for ANY relay: node check.mjs ws://127.0.0.1:9080
// Runs the handshake / routing rules of PROTOCOL.md against the given relay and prints PASS / FAIL.
import WebSocket from "ws";
const base = (process.argv[2] || "ws://127.0.0.1:9080").replace(/\/$/, "");
let failed = 0;
const check = (ok, what) => { console.log((ok ? "PASS " : "FAIL ") + what); if (!ok) failed++; };
const open = (path, hi) => new Promise((res, rej) => {
  const ws = new WebSocket(base + path); const inbox = []; const waiters = [];
  ws.on("message", (raw) => { const m = JSON.parse(raw.toString()); const w = waiters.shift(); if (w) w(m); else inbox.push(m); });
  ws.next = (ms = 2000) => new Promise((r, j) => { if (inbox.length) return r(inbox.shift()); waiters.push(r); setTimeout(() => j(new Error("timeout")), ms); });
  ws.on("open", () => { ws.send(JSON.stringify(hi)); res(ws); });
  ws.on("error", rej);
});
try {
  const host = await open("/v1/host", { t: "hi", role: "host", name: "Host", ver: "test" });
  const h = await host.next();
  check(h.t === "hello" && h.id === 1 && h.host === true && h.relay === 1 && /^[A-HJ-NP-Z2-9]{4}$/.test(h.code), "host gets hello (id 1, relay 1, 4 letter code)");
  const g1 = await open("/v1/room/" + h.code.toLowerCase(), { t: "hi", role: "join", code: h.code, name: "Anna", ver: "test" });
  const hello1 = await g1.next();
  check(hello1.t === "hello" && hello1.id === 2 && hello1.host === false && hello1.roster["1"] === "Host", "guest gets hello with id 2 and the roster (code is case-insensitive)");
  const peer = await host.next();
  check(peer.t === "peer" && peer.id === 2 && peer.name === "Anna" && peer.on === true, "host is told about the new peer");
  const g2 = await open("/v1/room/" + h.code, { t: "hi", role: "join", code: h.code, name: "Ben", ver: "test" });
  await g2.next(); await host.next(); await g1.next();
  g1.send(JSON.stringify({ t: "msg", to: 3, d: { k: "x" } }));
  const viaHost = await host.next();
  check(viaHost.t === "msg" && viaHost.from === 2 && viaHost.d.k === "x", "guest -> host (a guest cannot address another guest)");
  host.send(JSON.stringify({ t: "msg", to: 0, d: { k: "all", n: 1 } }));
  const a = await g1.next(), b = await g2.next();
  check(a.from === 1 && a.d.k === "all" && b.d.n === 1, "host -> everybody (to: 0), payload untouched");
  host.send(JSON.stringify({ t: "msg", to: 3, d: { k: "one" } }));
  check((await g2.next()).d.k === "one", "host -> one peer");
  g2.close();
  const left = await host.next();
  check(left.t === "peer" && left.id === 3 && left.on === false, "leaving guest -> peer on:false");
  await g1.next(); // g1 also hears about the leaving peer
  const bad = await open("/v1/room/ZZZZ", { t: "hi", role: "join", code: "ZZZZ", name: "X", ver: "test" });
  const err = await bad.next();
  check(err.t === "err" && err.m === "room_not_found", "unknown room -> err room_not_found");
  host.close();
  const hl = await g1.next();
  check(hl.t === "err" && hl.m === "host_left", "host leaves -> guests get err host_left");
} catch (e) { console.log("FAIL " + e.message); failed++; }
console.log(failed ? `${failed} check(s) failed` : "all checks passed");
process.exit(failed ? 1 : 0);
