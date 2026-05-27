#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PORT="${LLAMA_PORT:-8080}"
URL="http://127.0.0.1:${PORT}"
REFRESH="${1:-2}"

# Colors
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

# ── Parse a Prometheus metric value ─────────────────────────────
get_metric() {
    echo "$1" | awk -v key="$2" '$1 == key { print $2 }'
}

# ── Header: Machine Info (printed once) ─────────────────────────
print_header() {
    local chip cores mem_gb os_ver

    chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
    cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
    mem_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
    os_ver=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")

    # Model info from server
    local model_id
    model_id=$(curl -sf "${URL}/v1/models" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null \
        || echo "Unknown")

    clear
    echo -e "${BOLD}============================================${RESET}"
    echo -e "${BOLD}  Airplane Mode Monitor${RESET}"
    echo -e "${BOLD}============================================${RESET}"
    echo ""
    echo -e "${CYAN}Machine${RESET}"
    echo -e "  Chip:    ${BOLD}${chip}${RESET}"
    echo -e "  Cores:   ${cores}"
    echo -e "  Memory:  ${mem_gb} GB"
    echo -e "  macOS:   ${os_ver}"
    echo ""
    echo -e "${CYAN}Model${RESET}"
    echo -e "  Name:    ${BOLD}${model_id%.gguf}${RESET}"
    echo -e "  Server:  ${URL}"
    echo ""
    echo -e "${DIM}Refreshing every ${REFRESH}s. Ctrl+C to exit.${RESET}"
    echo ""
    echo -e "${CYAN}Live Stats${RESET}"
}

HEADER_END_LINE=17
STATS_LINES=6
HISTORY_START_LINE=$((HEADER_END_LINE + STATS_LINES + 1))

# ── Tracking for delta-based tok/s ──────────────────────────────
PREV_GEN_TOKENS=""
PREV_PROMPT_TOKENS=""
PREV_TIMESTAMP=""

# ── Run tracking ────────────────────────────────────────────────
WAS_ACTIVE=false
RUN_START_TOKENS=""
RUN_START_PROMPT=""
RUN_START_TIME=""
RUN_COUNT=0
HISTORY_LINES=()

# ── Main Loop ───────────────────────────────────────────────────
print_header

while true; do
    tput cup "$HEADER_END_LINE" 0 2>/dev/null || true

    local_metrics=$(curl -sf "${URL}/metrics" 2>/dev/null || echo "")
    local_slots=$(curl -sf "${URL}/slots" 2>/dev/null || echo "[]")

    if [ -z "$local_metrics" ]; then
        echo -e "  ${RED}Server not responding${RESET}                              "
        tput el 2>/dev/null || true; echo ""
        tput el 2>/dev/null || true; echo ""
        tput el 2>/dev/null || true; echo ""
        tput el 2>/dev/null || true; echo ""
        sleep "$REFRESH"
        continue
    fi

    # Parse metrics
    gen_tokens=$(get_metric "$local_metrics" "llamacpp:tokens_predicted_total")
    prompt_tokens=$(get_metric "$local_metrics" "llamacpp:prompt_tokens_total")
    avg_gen_tps=$(get_metric "$local_metrics" "llamacpp:predicted_tokens_seconds")
    avg_prompt_tps=$(get_metric "$local_metrics" "llamacpp:prompt_tokens_seconds")
    requests_processing=$(get_metric "$local_metrics" "llamacpp:requests_processing")

    # Slots
    active_slots=$(echo "$local_slots" | python3 -c "
import sys, json
slots = json.load(sys.stdin)
active = sum(1 for s in slots if s.get('is_processing', False))
print(f'{active}/{len(slots)}')
" 2>/dev/null || echo "?/?")

    # CPU/MEM of llama-server
    cpu_usage="" ; mem_usage=""
    if [ -f ".llama-server.pid" ]; then
        pid=$(cat ".llama-server.pid")
        ps_out=$(ps -p "$pid" -o %cpu=,%mem= 2>/dev/null || echo "")
        cpu_usage=$(echo "$ps_out" | awk '{printf "%.1f", $1}')
        mem_usage=$(echo "$ps_out" | awk '{printf "%.1f", $2}')
    fi

    # Compute live tok/s from deltas
    now=$(python3 -c "import time; print(time.time())")
    live_gen_tps="--"
    live_prompt_tps="--"

    if [ -n "$PREV_GEN_TOKENS" ] && [ -n "$PREV_TIMESTAMP" ]; then
        live_gen_tps=$(python3 -c "
dt = float('${now}') - float('${PREV_TIMESTAMP}')
dg = float('${gen_tokens}') - float('${PREV_GEN_TOKENS}')
if dt > 0 and dg > 0:
    print(f'{dg/dt:.1f}')
else:
    print('--')
")
        live_prompt_tps=$(python3 -c "
dt = float('${now}') - float('${PREV_TIMESTAMP}')
dp = float('${prompt_tokens}') - float('${PREV_PROMPT_TOKENS}')
if dt > 0 and dp > 0:
    print(f'{dp/dt:.1f}')
else:
    print('--')
")
    fi

    PREV_GEN_TOKENS="$gen_tokens"
    PREV_PROMPT_TOKENS="$prompt_tokens"
    PREV_TIMESTAMP="$now"

    # ── Detect run transitions (GENERATING -> IDLE) ─────────────
    is_active=false
    if [ "${requests_processing:-0}" != "0" ]; then
        is_active=true
    fi

    # Run just started
    if [ "$is_active" = true ] && [ "$WAS_ACTIVE" = false ]; then
        RUN_START_TOKENS="$gen_tokens"
        RUN_START_PROMPT="$prompt_tokens"
        RUN_START_TIME="$now"
    fi

    # Run just finished
    if [ "$is_active" = false ] && [ "$WAS_ACTIVE" = true ] && [ -n "$RUN_START_TIME" ]; then
        RUN_COUNT=$((RUN_COUNT + 1))
        summary=$(python3 -c "
import datetime
start = float('${RUN_START_TIME}')
end = float('${now}')
gen = float('${gen_tokens}') - float('${RUN_START_TOKENS}')
prompt = float('${prompt_tokens}') - float('${RUN_START_PROMPT}')
duration = end - start
gen_tps = gen / duration if duration > 0 else 0
prompt_tps = prompt / duration if duration > 0 else 0
ts = datetime.datetime.fromtimestamp(end).strftime('%H:%M:%S')
print(f'[{ts}] Run #{${RUN_COUNT}}  {duration:.1f}s  |  {gen:.0f} gen tokens @ {gen_tps:.1f} tok/s  |  {prompt:.0f} prompt tokens @ {prompt_tps:.1f} tok/s')
")
        HISTORY_LINES+=("$summary")
    fi

    WAS_ACTIVE="$is_active"

    # ── Status line ─────────────────────────────────────────────
    if [ "$is_active" = true ]; then
        status="${GREEN}${BOLD}GENERATING${RESET}"
    else
        status="${DIM}IDLE${RESET}      "
    fi

    # Render live stats
    echo -e "  Status:  ${status}                              "
    echo -e "  Slots:   ${BOLD}${active_slots}${RESET}  active                    "
    echo -e "  Tokens:  ${BOLD}${gen_tokens%.*}${RESET} generated  |  ${BOLD}${prompt_tokens%.*}${RESET} prompt          "

    if [ "$live_gen_tps" != "--" ]; then
        echo -e "  Speed:   ${GREEN}${BOLD}${live_gen_tps} tok/s${RESET} generation  |  ${BOLD}${live_prompt_tps} tok/s${RESET} prompt      "
    elif [ "$avg_gen_tps" != "0" ] && [ -n "$avg_gen_tps" ]; then
        echo -e "  Speed:   ${BOLD}${avg_gen_tps} tok/s${RESET} gen (avg)  |  ${BOLD}${avg_prompt_tps} tok/s${RESET} prompt (avg)   "
    else
        echo -e "  Speed:   ${DIM}waiting for activity...${RESET}                    "
    fi

    if [ -n "$cpu_usage" ]; then
        echo -e "  Process: CPU ${BOLD}${cpu_usage}%${RESET}  |  MEM ${BOLD}${mem_usage}%${RESET}                    "
    else
        tput el 2>/dev/null || true; echo ""
    fi

    # ── Render run history ──────────────────────────────────────
    echo ""
    if [ ${#HISTORY_LINES[@]} -gt 0 ]; then
        echo -e "${CYAN}Completed Runs${RESET}"
        # Show last 8 runs
        start_idx=0
        if [ ${#HISTORY_LINES[@]} -gt 8 ]; then
            start_idx=$(( ${#HISTORY_LINES[@]} - 8 ))
        fi
        for (( i=start_idx; i<${#HISTORY_LINES[@]}; i++ )); do
            echo -e "  ${YELLOW}${HISTORY_LINES[$i]}${RESET}"
        done
        tput el 2>/dev/null || true
    else
        tput el 2>/dev/null || true; echo ""
    fi

    # Clear leftover lines
    for _ in 1 2 3; do
        tput el 2>/dev/null || true; echo ""
    done

    sleep "$REFRESH"
done
