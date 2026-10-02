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
device:P  →  NODE_ADDR:Q       (SideStore dials NODE_ADDR)
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

1. ```sh
   cp .env.example .env      # fill in TS_AUTHKEY
   docker compose up -d --build
   ```
   The container picks up its own Tailscale IP automatically
   (`docker logs sidestore-vpn | grep "node address"`). This is the
   **reflect address** — call it `NODE_ADDR`. No `+1`, no editing the
   machine IP in the admin console.

2. (Recommended) On your router, forward **UDP 41642** to the Docker host.
   This lets peers connect directly instead of through a DERP relay.
   Check with `tailscale ping <NODE_ADDR>`: it should say
   `via <public IP>:41642`, not `via DERP`.

3. On the iOS device: SideStore → Settings → **Connection Config** →
   turn **Use Local VPN off** (Remote Endpoint mode) → **Device IP** =
   `NODE_ADDR`, leave RemotePair Port empty → Confirm.

4. Verify: on the iOS device (Wi-Fi + Tailscale on), SideStore → Settings →
   Health Check should show Device Reachability green. Refresh away.

> **Why Remote Endpoint, not Use Local VPN?** On SideStore 0.7.0
> (LiveContainer 3.8.10 nightly), Local VPN mode never reached the device over
> Tailscale (Health Check: `NoDevice … DeviceEndpointNotInitialized`), even with
> a direct connection — while Remote Endpoint mode with the same IP worked right
> away. Remote Endpoint also means the reflector no longer has to sit at
> `<device IP> + 1`. Raising Developer Options → Device (TCP) Probe Timeout to
> 2000 ms helps on a slow/relayed path.
>
> Still want Local VPN mode? Set `NODE_ADDR` in `.env` to
> `<device Tailscale IP> + 1` and set the same IPv4 on this machine in the
> [admin console](https://login.tailscale.com/admin/machines).

## Device IP changes / multiple devices

The reflector sends every packet back to whoever sent it, so it doesn't care
about the device's IP: nothing to update when it changes. Multiple iOS devices
should be able to share one reflector (each sets Device IP = `NODE_ADDR`) —
not tested yet.

## Credits

- [xddxdd/sidestore-vpn](https://github.com/xddxdd/sidestore-vpn) — the
  original reflector this is forked from (public domain / Unlicense)
- [SideStore](https://github.com/SideStore/SideStore) &
  [minimuxer](https://github.com/SideStore/minimuxer)
