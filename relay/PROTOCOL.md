# Relay protocol v1 - how to build your own relay

Audience: a person (or an LLM) who wants to run an own relay because the built-in default one is gone. In the game:
**Play online -> "Own relay server ..."** and enter your address (`wss://...` or `ws://...`); leave the field empty for the
built-in default. Everybody in a room has to use the same relay.

A relay is a dumb message forwarder. It keeps **no game state**, does not look into the game payload and never needs an
update when the game changes (only the envelope below is its business). Two reference implementations exist:

| Where | What |
|---|---|
| `relay/template/relay_node.mjs` | ~100 lines Node.js + `ws`, the easiest starting point (`cd relay/template && npm install && node relay_node.mjs`) |
| `relay/cloudflare/worker.js` | Cloudflare Worker + Durable Object (free plan), the production one |
| `tools/relay_server.gd` | the same in GDScript, runs with `godot --headless --script res://tools/relay_server.gd -- --port=9080` |

**Conformance check for any implementation** (any language, any host): `cd relay/template && npm install && node check.mjs wss://your.relay`.
It plays host + two guests through every rule below and prints PASS / FAIL.

## Transport

* WebSocket, **text frames, one JSON object per frame**. No binary frames.
* The game connects outbound only, so a relay works behind any NAT. For `wss://` terminate TLS in front of it (Caddy,
  nginx, Cloudflare ...). Allow frames of at least 1 MiB (a turn snapshot is some tens of KiB).
* A plain HTTP `GET` (no `Upgrade`) should answer `{"service":"medieval-madness-relay","proto":1}` - handy for a health check.

## Endpoints (the prefix `/v1` is `RELAY_PROTO`)

| Request | Meaning |
|---|---|
| `GET /v1/host` (WebSocket) | open a **new room**; the relay picks a free 4 letter code |
| `GET /v1/room/<CODE>` (WebSocket) | join room `<CODE>` (case-insensitive) |

Anything else: close / 404. A breaking change of the envelope gets a new prefix (`/v2/...`), served next to `/v1`.

Room codes: 4 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no `0 O 1 I`), unique among running rooms.
Max **8 peers** per room (host + 7 guests).

## Frames, client -> relay

```json
{"t":"hi","role":"host","name":"Anna","ver":"1.2.3"}            // FIRST frame after connecting (host: /v1/host)
{"t":"hi","role":"join","code":"ABCD","name":"Ben","ver":"..."}  // FIRST frame after connecting (guest: /v1/room/ABCD)
{"t":"msg","to":<id>,"d":{...}}                                  // forward d (any JSON object) to peer <id>; to 0 = everybody else
{"t":"ping"}                                                     // keep-alive every 15 s, ignore it (no answer needed)
```

Frames before `hi` other than `hi` are ignored. `name` is cut to 24 characters. Unknown frame types are ignored.

## Frames, relay -> client

```json
{"t":"hello","id":2,"code":"ABCD","host":false,"relay":1,"roster":{"1":"Anna","2":"Ben"}}
{"t":"peer","id":3,"name":"Carl","on":true}      // somebody joined  (on:false = left)
{"t":"msg","from":2,"d":{...}}                   // d is exactly what the sender gave, untouched
{"t":"err","m":"room_not_found"}                 // followed by closing the socket
```

* `hello` answers `hi`. `id` is the peer id: **the host is always 1**, guests get 2, 3, ... in order of joining (never reused
  inside a room). `relay` MUST be `1` - the game refuses a relay with another value ("relay outdated").
  `roster` maps id (as string) -> name and includes the new peer itself.
* When a guest joins, every **other** peer gets `peer {on:true}`; when one leaves, everybody left gets `peer {on:false}`.

## Routing rules (star topology)

* A **guest** can only talk to the host: whatever `to` says, the frame goes to peer 1.
* The **host** can address `to: <id>` (one guest) or `to: 0` (all guests, not itself). Missing `to` from the host means 1.
* The relay stamps `from` with the sender's id. It never changes or inspects `d`.

## Errors (`err.m`, then close with code 1000)

| `m` | When |
|---|---|
| `room_not_found` | guest joins a code without a running host |
| `room_full` | 8 peers already inside |
| `host_left` | sent to every guest when the host disconnects; the room is gone afterwards |

If the host disconnects the room ends for everybody; a guest that disconnects only produces `peer {on:false}`.

## Checklist for a new implementation

1. Both endpoints, WebSocket upgrade, JSON text frames.
2. `hi` -> `hello` (host id 1, `relay:1`, roster) and `peer` to the others.
3. `msg` routing exactly as above (guest -> host only, host -> one / all).
4. `peer on:false` on leaving guests, `err host_left` + close on a leaving host, cleanup of the room.
5. Run `node relay/template/check.mjs <your url>`; then try a real game: host + one guest with `--autotest=nethost` /
   `--autotest=netjoin` (see `relay/README.md`, "Tests"), the NETLOG lines of both must agree.

Optional hardening: limit message size (e.g. 2 MiB), rate-limit per connection, drop idle sockets after ~60 s without a frame
(clients ping every 15 s), cap the number of rooms per IP.
