# sidestore-vpn-tailscale

English | [繁體中文](README.zh-TW.md)

Refresh [SideStore](https://sidestore.io) (nightly, new `idevice`-based
architecture) over [Tailscale](https://tailscale.com) — no LocalDevVPN,
no VPN switching. Keep Tailscale always-on and refresh from any Wi-Fi.

Based on [xddxdd/sidestore-vpn](https://github.com/xddxdd/sidestore-vpn),
adapted for the new SideStore architecture (2026+ nightlies / 0.6.3+).

## Why the old approach stopped working

The old SideStore minimuxer dialed a hardcoded `10.7.0.1`, so a reflector
advertising the `10.7.0.1/32` subnet route was enough. The new Swift
minimuxer instead **derives its dial target from the active VPN interface:
`<utun interface IP> + 1`** (for a /32 point-to-point utun — which is what
Tailscale creates). With Tailscale connected, SideStore dials
`<your device's Tailscale IP> + 1`, and `10.7.0.1` is never used.

Two extra gotchas discovered along the way:

- Tailscale **silently refuses to distribute subnet routes inside its own
  CGNAT range** (100.64.0.0/10). The admin console lets you approve such a
  route, but peers never receive it. So the reflect address can't be served
  as a subnet route — instead, this node's **own Tailscale IP** is set to
  the reflect address, and NAT steers the traffic into the reflector TUN.
- `--snat-subnet-routes=false` is **required**. Tailscale's default
  MASQUERADE rewrites the packet source before the reflector sees it,
  which bounces reflected traffic back into the container itself.

## How it works

```
device:P  →  NODE_ADDR:Q       (minimuxer dials <device IP>+1)
   DNAT   →  10.7.0.1:Q        (into the reflector TUN)
  reflect →  swap src/dst      (58-line Rust program)
   SNAT   →  NODE_ADDR:P  →  device:Q   (back to the device's own
                                          lockdownd/RSD services)
```

The iOS device ends up talking to itself, which is exactly what SideStore
needs to install/refresh apps.

## Requirements

- A Linux box on your tailnet that can run Docker (NAS, server, etc.)
- SideStore nightly with an RPPairing pairing file (via iloader)
- **The iOS device must be connected to some Wi-Fi network.** iOS only
  opens the lockdownd/RSD services while associated to Wi-Fi. Cellular-only
  refresh is impossible at the OS level — with this tool, with LocalDevVPN,
  with anything. (Verified empirically: ports 62078/49152 are closed on
  cellular, open on Wi-Fi.)

## Setup

1. Find your iOS device's Tailscale IP (Tailscale app → device). Your
   reflect address is that IP **+ 1**: e.g. `100.101.102.103` → `100.101.102.104`.

2. ```sh
   cp .env.example .env      # fill in TS_AUTHKEY and NODE_ADDR
   docker compose up -d --build
   ```

3. In the [Tailscale admin console](https://login.tailscale.com/admin/machines),
   find the new `sidestore-vpn` machine → **Edit machine IPv4 address** →
   set it to the same value as `NODE_ADDR`.

4. Verify: `ping <NODE_ADDR>` from any tailnet device should reply.
   On the iOS device (Wi-Fi + Tailscale on), SideStore → Settings →
   Health Check should show Tunnel Peer IP = `NODE_ADDR` and
   Device Reachability green. Refresh away.

## If your device's Tailscale IP changes

The reflect address is derived from the device IP, so update both:
`NODE_ADDR` in `.env` **and** the machine IPv4 in the admin console,
then `docker compose up -d --build`.

Multiple iOS devices need one reflector each (one node per `<IP>+1`).

## Credits

- [xddxdd/sidestore-vpn](https://github.com/xddxdd/sidestore-vpn) — the
  original reflector this is forked from (public domain / Unlicense)
- [SideStore](https://github.com/SideStore/SideStore) &
  [minimuxer](https://github.com/SideStore/minimuxer)
