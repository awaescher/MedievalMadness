# Online play (up to 8 players)

The game talks to a tiny **relay** over a WebSocket (outbound connections only, so it works behind every router and
firewall, no port forwarding). The relay only forwards messages between the players of a room; it keeps no game state.
Players join with a 4 letter **room code**.

## Option A: Cloudflare Workers (nothing to operate, free plan)

The file that runs on Cloudflare is **`relay/cloudflare/worker.js`** (plus `wrangler.toml`, which tells Cloudflare about the
Durable Object that holds a room). One-time setup, needs a free Cloudflare account and Node.js:

```bash
cd relay/cloudflare
npx wrangler login      # opens the browser: "Allow"
npx wrangler deploy     # first time it asks for a name for your workers.dev address
```

`wrangler` prints the address of your worker, e.g. `https://mm-relay.yourname.workers.dev`. In the game open **Play online**
and enter it with `wss://` instead of `https://`: `wss://mm-relay.yourname.workers.dev`. Everybody who plays with you needs
the same address once (it is remembered; the default is built in: `Cfg.DEFAULT_RELAY`, currently `wss://mm-relay.twilight-mouse-b997.workers.dev`).

Check it: open the address in a browser, it answers `{"service":"medieval-madness-relay","proto":1}`. Logs: `npx wrangler tail`.
`npm test` in `relay/cloudflare` runs the relay logic against a mock of the Cloudflare runtime (12 checks).

*Dashboard instead of wrangler:* Workers & Pages -> Create -> Worker -> paste `worker.js` -> Deploy, then Settings ->
Bindings -> Durable Object (variable `ROOMS`, class `Room`, a new SQLite class). The wrangler route is the tested one.

Free plan: a room costs about 450 GB-s of Durable Object time per hour (the daily allowance is 13,000), so 14+ room-hours a
day are free; a re-deploy drops running rooms, so deploy while nobody plays.

## Option C: write your own relay

The default relay is hidden in the game UI; under *Play online -> Own relay server ...* anybody can enter another address.
**[PROTOCOL.md](PROTOCOL.md)** is the complete spec (about 2 pages), `relay/template/relay_node.mjs` is a runnable Node.js
starting point and `relay/template/check.mjs` tests any relay against the spec.

## Versions: when does what have to be updated?

| What changed | What you must do |
|---|---|
| Anything inside the game (weapons, rules, new message kinds, sync) | Nothing for the relay: it forwards the payload untouched. Players on different **game versions** can still play together (the host shows a warning). |
| A change that makes two builds drift apart (message formats, shot / placement / snapshot, RNG use) | Raise `Net.NET_VERSION` in `scripts/autoload/net.gd`. Players with different values are refused at joining ("please update the game"). |
| The relay envelope (`hi`, `hello`, `peer`, `msg`, `err`) | Raise `RELAY_PROTO` in `worker.js` **and** in `net.gd`, and serve the new URL prefix (`/v2/...`) next to `/v1` in the same worker, so old builds keep working. A game that meets a relay with another protocol says "relay outdated, deploy the current worker.js". |

## Option B: self-hosted relay (any machine that can run Godot)

```bash
godot --headless --path . --script res://tools/relay_server.gd -- --port=9080
```

Players use `ws://<address of that machine>:9080`. Put a TLS reverse proxy in front of it if you want `wss://`.
Handy for a LAN party: run it on one PC and use `ws://192.168.x.x:9080`.

## Playing

1. **Host:** menu -> *Play online*, enter your name and the relay address, press *Host a game*. A room code appears.
   Give it to your friends, close the window, set the match options in the main menu (seed, map, players, ...) and press
   *START ONLINE GAME* when everybody is in.
2. **Guests:** menu -> *Play online*, name, relay address, the code, *Join*. Wait for the host to start.
3. Every connected person gets a seat (host = seat 1, then in order of joining); the remaining seats are CPU players
   controlled by the host.

Rules of thumb: weather and random events are off online; the pause menu does not stop the game; a player who leaves is
out and their catapults disappear; if the host leaves the game ends for everybody.

## Tests

`tests/` has no GUI test for this, but you can run a whole online match with three headless processes:

```bash
godot --headless --path . --script res://tools/relay_server.gd -- --port=9081 &
godot --headless --path . -- --autotest=nethost --relay=ws://127.0.0.1:9081 --peers=2 --players=4 --turns=8 &
godot --headless --path . -- --autotest=netjoin --relay=ws://127.0.0.1:9081 --code=<printed code> --name=Anna --turns=8 &
godot --headless --path . -- --autotest=netjoin --relay=ws://127.0.0.1:9081 --code=<printed code> --name=Ben --turns=8 &
```

Each process prints `NETLOG` lines (turn, wind, structure hash, ...). They must agree.
