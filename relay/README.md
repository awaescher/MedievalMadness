# Online play (up to 8 players)

The game talks to a tiny **relay** over a WebSocket (outbound connections only, so it works behind every router and
firewall, no port forwarding). The relay only forwards messages between the players of a room; it keeps no game state.
Players join with a 4 letter **room code**.

## Option A: Cloudflare Workers (nothing to operate, free plan)

One-time setup (needs a free Cloudflare account and Node.js):

```bash
cd relay/cloudflare
npx wrangler login
npx wrangler deploy
```

`wrangler` prints the address of your worker, e.g. `https://mm-relay.yourname.workers.dev`. In the game open
**Play online** and enter it as the relay server, but with `wss://` instead of `https://`:
`wss://mm-relay.yourname.workers.dev`. Everybody who plays with you enters the same address once (it is remembered).

Note: `relay/cloudflare/worker.js` was written against the same protocol as the Godot relay below, which is what the
automated tests use. It has not been run on Cloudflare from this repository, so check the first deploy with one friend.

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
