class FakeSock {
  constructor() { this.l = {}; this.sent = []; this.closed = false; }
  accept() {}
  addEventListener(t, f) { (this.l[t] ||= []).push(f); }
  send(s) { this.sent.push(JSON.parse(s)); }
  close() { if (this.closed) return; this.closed = true; (this.l.close || []).forEach(f => f()); }
  emit(obj) { (this.l.message || []).forEach(f => f({ data: JSON.stringify(obj) })); }
}
const pairs = [];
globalThis.WebSocketPair = class { constructor() { this[0] = new FakeSock(); this[1] = new FakeSock(); pairs.push(this[1]); } };
globalThis.Response = class { constructor(body, init = {}) { this.body = body; this.status = init.status || 200; this.webSocket = init.webSocket; } };
globalThis.Request = class { constructor(url) { this.url = url; this.headers = { get: k => (k === "Upgrade" ? "websocket" : null) }; } };
const mod = await import("./worker.js");
const rooms = new Map();
const env = { ROOMS: { idFromName: n => n, get: id => { if (!rooms.has(id)) rooms.set(id, new mod.Room({}, {})); const r = rooms.get(id); return { fetch: req => r.fetch(req) }; } } };
const mk = path => ({ url: "https://x" + path, headers: { get: k => (k === "Upgrade" ? "websocket" : null) } });
const assert = (c, m) => { if (!c) { console.log("FAIL", m); process.exitCode = 1; } else console.log("ok  ", m); };
await mod.default.fetch(mk("/v1/host"), env);
const H = pairs[0];
H.emit({ t: "hi", role: "host", name: "Host", ver: "1" });
const hello = H.sent[0];
assert(hello.t === "hello" && hello.host && hello.relay === 1 && hello.code.length === 4, "host gets hello with code and relay proto " + JSON.stringify(hello));
await mod.default.fetch(mk("/v1/room/" + hello.code.toLowerCase()), env);
const A = pairs[1];
A.emit({ t: "hi", role: "join", name: "Anna" });
assert(A.sent[0].t === "hello" && A.sent[0].id === 2 && A.sent[0].roster["1"] === "Host", "guest joins as id 2");
assert(H.sent.some(m => m.t === "peer" && m.on && m.id === 2), "host is told about the guest");
await mod.default.fetch(mk("/v1/room/" + hello.code), env);
const B = pairs[2];
B.emit({ t: "hi", role: "join", name: "Ben" });
assert(A.sent.some(m => m.t === "peer" && m.id === 3), "first guest is told about the second");
A.emit({ t: "msg", to: 3, d: { k: "x" } });
assert(H.sent.some(m => m.t === "msg" && m.from === 2 && m.d.k === "x"), "a guest's message goes to the host only");
assert(!B.sent.some(m => m.t === "msg"), "...and not to the other guest");
H.emit({ t: "msg", to: 0, d: { k: "y" } });
assert(A.sent.some(m => m.t === "msg" && m.from === 1) && B.sent.some(m => m.t === "msg" && m.from === 1), "host broadcast reaches everybody");
H.emit({ t: "msg", to: 3, d: { k: "z" } });
assert(B.sent.filter(m => m.t === "msg").length === 2 && A.sent.filter(m => m.t === "msg").length === 1, "host can address one peer");
B.close();
assert(H.sent.some(m => m.t === "peer" && !m.on && m.id === 3), "leaving guest is announced");
const nf = await mod.default.fetch(mk("/v1/room/ZZZZ"), env);
const C = pairs[3];
C.emit({ t: "hi", role: "join", name: "Nobody" });
assert(C.sent[0] && C.sent[0].m === "room_not_found", "unknown room is reported");
H.close();
assert(A.sent.some(m => m.t === "err" && m.m === "host_left"), "guests are told when the host leaves");
const r = await mod.default.fetch(mk("/host"), env);
assert(r.status === 404, "old unversioned path is gone");
