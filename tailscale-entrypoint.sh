#!/bin/sh
set -e

# NODE_ADDR: this node's Tailscale IP, which must be set to
# <your iOS device's Tailscale IP> + 1 in the Tailscale admin console.
# No default on purpose — see README.
if [ -z "$NODE_ADDR" ]; then
    echo "ERROR: NODE_ADDR is not set. Set it to <device tailscale IP> + 1 (see README)." >&2
    exit 1
fi

# Internal address of the reflector TUN (container-internal only)
REFLECT_ADDR="${REFLECT_ADDR:-10.7.0.1}"

# Packets to the node IP -> steer into the reflector TUN;
# reflected packets -> rewrite source back to the node IP
iptables -t nat -A PREROUTING -d "$NODE_ADDR" -j DNAT --to-destination "$REFLECT_ADDR"
iptables -t nat -A POSTROUTING -s "$REFLECT_ADDR" -j SNAT --to-source "$NODE_ADDR"

/sidestore-vpn &
exec /usr/local/bin/containerboot
