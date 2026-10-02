#!/bin/sh
set -e

# Internal address of the reflector TUN (container-internal only)
REFLECT_ADDR="${REFLECT_ADDR:-10.7.0.1}"

/sidestore-vpn &
/usr/local/bin/containerboot &
BOOT_PID=$!
trap 'kill -TERM "$BOOT_PID" 2>/dev/null' TERM INT

# NODE_ADDR: this node's Tailscale IP. Optional — by default wait for
# tailscaled to come up and use whatever IP the tailnet assigned.
until [ -n "$NODE_ADDR" ]; do
    NODE_ADDR=$(tailscale --socket="${TS_SOCKET:-/tmp/tailscaled.sock}" ip -4 2>/dev/null || true)
    [ -n "$NODE_ADDR" ] || sleep 1
done
echo "reflector: node address $NODE_ADDR"

# Packets to the node IP -> steer into the reflector TUN;
# reflected packets -> rewrite source back to the node IP
iptables -t nat -A PREROUTING -d "$NODE_ADDR" -j DNAT --to-destination "$REFLECT_ADDR"
iptables -t nat -A POSTROUTING -s "$REFLECT_ADDR" -j SNAT --to-source "$NODE_ADDR"

wait "$BOOT_PID"
