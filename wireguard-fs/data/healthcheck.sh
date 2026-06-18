#!/bin/bash

# Container healthcheck: bwg show must list a peer and at least one live path
# (control handshake and/or a green data endpoint).

set -euo pipefail

WG_IF="${MON_WG_INTERFACE:-}"
if [ -n "$WG_IF" ]; then
    mapfile -t wg_elements < <(/usr/bin/bwg show "$WG_IF" 2>/dev/null || true)
else
    mapfile -t wg_elements < <(/usr/bin/bwg show 2>/dev/null || true)
fi

if [ ${#wg_elements[@]} -le 5 ]; then
    echo "bwg not started"
    exit 1
fi

has_peer=0
has_handshake=0
has_green=0

for line in "${wg_elements[@]}"; do
    [[ "$line" == peer:* ]] && has_peer=1
    [[ "$line" == *"latest handshake:"* ]] && has_handshake=1
    [[ "$line" == *"state:"* && "$line" == *"green"* ]] && has_green=1
done

if [ "$has_peer" -eq 1 ] && { [ "$has_handshake" -eq 1 ] || [ "$has_green" -eq 1 ]; }; then
    exit 0
fi

echo "unhealthy: peer=$has_peer handshake=$has_handshake green=$has_green"
exit 1
