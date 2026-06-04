#!/bin/sh
#
# WireGuard peer endpoint metrics monitor for Home Assistant.
# Runs from cron once per minute.
#

set -u

# cron starts jobs with a stripped environment, so the container's Docker ENV
# (MON_*) is not visible here. Pull those vars from PID 1's environment.
if [ -r /proc/1/environ ]; then
    while IFS= read -r _envline; do
        case "$_envline" in
            MON_*) export "$_envline" ;;
        esac
    done <<EOF
$(tr '\0' '\n' < /proc/1/environ)
EOF
    unset _envline
fi

MON_ENABLED="${MON_ENABLED:-1}"
[ "$MON_ENABLED" = "1" ] || exit 0

MON_WG_INTERFACE="${MON_WG_INTERFACE:-wg2}"
MON_WG_PEER_PREFIX="${MON_WG_PEER_PREFIX:-}"
MON_HA_URL="${MON_HA_URL:-}"
MON_HA_TOKEN="${MON_HA_TOKEN:-}"
MON_BASE_NAME="${MON_BASE_NAME:-msk}"
MON_CURL_TIMEOUT="${MON_CURL_TIMEOUT:-5}"
MON_VERBOSE="${MON_VERBOSE:-0}"

log() {
    [ "$MON_VERBOSE" = "1" ] && echo "[wg-peer-monitor] $*" >&2
    return 0
}

check_requirements() {
    command -v bwg >/dev/null 2>&1 || { echo "[wg-peer-monitor] bwg not found" >&2; return 1; }
    command -v jq >/dev/null 2>&1 || { echo "[wg-peer-monitor] jq not found" >&2; return 1; }
    command -v curl >/dev/null 2>&1 || { echo "[wg-peer-monitor] curl not found" >&2; return 1; }
    [ -n "$MON_HA_URL" ] || { echo "[wg-peer-monitor] MON_HA_URL is empty" >&2; return 1; }
    [ -n "$MON_HA_TOKEN" ] || { echo "[wg-peer-monitor] MON_HA_TOKEN is empty" >&2; return 1; }
    [ -n "$MON_WG_PEER_PREFIX" ] || { echo "[wg-peer-monitor] MON_WG_PEER_PREFIX is empty" >&2; return 1; }
    return 0
}

report_metric() {
    RM_STATE=$1
    RM_METRIC=$2
    RM_METRIC_FRIENDLY=$3
    RM_UNIT=$4
    RM_EXTRA_ATTRS=$5
    RM_DATE_UPD=$(date +'%Y/%m/%d %H:%M:%S')

    ATTRS_JSON="\"last_updated\":\"$RM_DATE_UPD\",\"friendly_name\":\"$RM_METRIC_FRIENDLY\""
    if [ -n "$RM_UNIT" ]; then
        ATTRS_JSON="$ATTRS_JSON,\"unit_of_measurement\":\"$RM_UNIT\""
    fi
    if [ -n "$RM_EXTRA_ATTRS" ]; then
        ATTRS_JSON="$ATTRS_JSON,$RM_EXTRA_ATTRS"
    fi

    curl -sS -m "$MON_CURL_TIMEOUT" -X POST \
        -H "Authorization: Bearer $MON_HA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"state\": \"$RM_STATE\", \"attributes\": {$ATTRS_JSON}}" \
        "${MON_HA_URL}/api/states/sensor.$RM_METRIC" >/dev/null || {
        echo "[wg-peer-monitor] failed to report metric: $RM_METRIC" >&2
        return 1
    }
}

direction_to_metric() {
    case "$1" in
        initiator) echo "out" ;;
        responder) echo "in" ;;
        *) echo "unknown" ;;
    esac
}

endpoint_to_metric_token() {
    ENDPOINT_STR=$1

    if [ -z "$ENDPOINT_STR" ] || [ "$ENDPOINT_STR" = "null" ]; then
        echo "unknown_0"
        return
    fi

    if [ "${ENDPOINT_STR#\[}" != "$ENDPOINT_STR" ]; then
        HOST=$(echo "$ENDPOINT_STR" | sed -E 's/^\[([^]]+)\]:.*/\1/')
        PORT=$(echo "$ENDPOINT_STR" | sed -E 's/^.*:([0-9]+)$/\1/')
    else
        HOST=${ENDPOINT_STR%:*}
        PORT=${ENDPOINT_STR##*:}
    fi

    if echo "$HOST" | grep -q ':'; then
        FIRST_HEXTET=$(echo "$HOST" | awk -F: '{for(i=1;i<=NF;i++) if($i!=""){print $i; exit}}')
        LAST_HEXTET=$(echo "$HOST" | awk -F: '{for(i=NF;i>=1;i--) if($i!=""){print $i; exit}}')
        HOST_CRC=$(printf '%s' "$HOST" | cksum | awk '{print $1}')
        HOST_CRC_SHORT=$(printf '%s' "$HOST_CRC" | cut -c1-5)
        HOST_TOKEN="v6_${FIRST_HEXTET}_${LAST_HEXTET}_${HOST_CRC_SHORT}"
    else
        HOST_TOKEN=$(echo "$HOST" | tr '.' '_' | tr -cd 'A-Za-z0-9_')
    fi

    PORT_TOKEN=$(echo "$PORT" | tr -cd '0-9')
    [ -n "$HOST_TOKEN" ] || HOST_TOKEN="unknown"
    [ -n "$PORT_TOKEN" ] || PORT_TOKEN="0"
    echo "${HOST_TOKEN}_${PORT_TOKEN}"
}

report_endpoint_metrics() {
    ENDPOINT=$1
    DIRECTION_RAW=$2
    RTT_MS=$3
    STATE=$4
    LAST_RX_AGO_SEC=$5
    AVG_LOSS_PER_1000=$6
    TX_RANK=$7
    RX_BYTES=$8
    TX_BYTES=$9

    DIR=$(direction_to_metric "$DIRECTION_RAW")
    EP_TOKEN=$(endpoint_to_metric_token "$ENDPOINT")
    METRIC_STEM="${MON_WG_INTERFACE}_uplink_${DIR}_${EP_TOKEN}"

    log "reporting ${METRIC_STEM}"
    report_metric "$RTT_MS" "${MON_BASE_NAME}_${METRIC_STEM}_rtt_ms" "${METRIC_STEM} RTT" "ms" "\"state_class\":\"measurement\",\"endpoint\":\"${ENDPOINT}\",\"direction\":\"${DIR}\""
    report_metric "$STATE" "${MON_BASE_NAME}_${METRIC_STEM}_state" "${METRIC_STEM} State" "" "\"endpoint\":\"${ENDPOINT}\",\"direction\":\"${DIR}\""
    report_metric "$LAST_RX_AGO_SEC" "${MON_BASE_NAME}_${METRIC_STEM}_last_rx_ago_sec" "${METRIC_STEM} Last RX Ago" "s" "\"state_class\":\"measurement\",\"endpoint\":\"${ENDPOINT}\",\"direction\":\"${DIR}\""
    report_metric "$AVG_LOSS_PER_1000" "${MON_BASE_NAME}_${METRIC_STEM}_avg_loss_per_1000" "${METRIC_STEM} Average Loss" "" "\"state_class\":\"measurement\",\"endpoint\":\"${ENDPOINT}\",\"direction\":\"${DIR}\""
    report_metric "$TX_RANK" "${MON_BASE_NAME}_${METRIC_STEM}_tx_rank" "${METRIC_STEM} TX Rank" "" "\"state_class\":\"measurement\",\"endpoint\":\"${ENDPOINT}\",\"direction\":\"${DIR}\""
    report_metric "$RX_BYTES" "${MON_BASE_NAME}_${METRIC_STEM}_rx_bytes" "${METRIC_STEM} RX Bytes" "B" "\"state_class\":\"measurement\",\"endpoint\":\"${ENDPOINT}\",\"direction\":\"${DIR}\""
    report_metric "$TX_BYTES" "${MON_BASE_NAME}_${METRIC_STEM}_tx_bytes" "${METRIC_STEM} TX Bytes" "B" "\"state_class\":\"measurement\",\"endpoint\":\"${ENDPOINT}\",\"direction\":\"${DIR}\""
}

process_wg_peer() {
    if ! ip link show "$MON_WG_INTERFACE" >/dev/null 2>&1; then
        log "interface $MON_WG_INTERFACE does not exist"
        return 0
    fi

    METRICS_JSON=$(bwg metrics "$MON_WG_INTERFACE" "$MON_WG_PEER_PREFIX" 2>/dev/null || true)
    if [ -z "$METRICS_JSON" ]; then
        echo "[wg-peer-monitor] empty output from bwg metrics for ${MON_WG_INTERFACE}/${MON_WG_PEER_PREFIX}" >&2
        return 1
    fi

    ENDPOINT_ROWS=$(echo "$METRICS_JSON" | jq -r '
        .[] | .endpoints[]? |
        [
          (.endpoint // "null"),
          (.direction // "unknown"),
          (.rtt_ms // -1),
          (.state // "unknown"),
          (.last_rx_ago_sec // -1),
          (.avg_loss_per_1000 // -1),
          (.tx_rank // -1),
          (.rx_bytes // -1),
          (.tx_bytes // -1)
        ] | @tsv
    ' 2>/dev/null)

    if [ -z "$ENDPOINT_ROWS" ]; then
        log "no endpoints found for ${MON_WG_INTERFACE}/${MON_WG_PEER_PREFIX}"
        return 0
    fi

    printf '%s\n' "$ENDPOINT_ROWS" | while IFS='	' read -r ENDPOINT DIRECTION RTT_MS STATE LAST_RX_AGO_SEC AVG_LOSS_PER_1000 TX_RANK RX_BYTES TX_BYTES; do
        report_endpoint_metrics \
            "$ENDPOINT" \
            "$DIRECTION" \
            "$RTT_MS" \
            "$STATE" \
            "$LAST_RX_AGO_SEC" \
            "$AVG_LOSS_PER_1000" \
            "$TX_RANK" \
            "$RX_BYTES" \
            "$TX_BYTES"
    done
}

check_requirements || exit 0
process_wg_peer
