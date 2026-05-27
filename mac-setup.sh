#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

[ -f .env ] && source .env

QUANT="${QUANT:-Q4_K_M}"
MTP="${MTP:-false}"
PORT="${LLAMA_PORT:-8080}"
CTX="${LLAMA_CTX:-32768}"
NGL="${GPU_LAYERS:-99}"
PID_FILE="$SCRIPT_DIR/.llama-server.pid"
LOG_FILE="$SCRIPT_DIR/.llama-server.log"

usage() {
    echo "Usage: ./mac-setup.sh [start|stop|status|logs]"
    echo ""
    echo "  start   Download model (if needed), start llama-server, install Pi"
    echo "  stop    Stop llama-server"
    echo "  status  Check if llama-server is running"
    echo "  logs    Tail llama-server logs"
}

do_start() {
    echo "============================================"
    echo "  Airplane Mode - Qwen 3.6 27B (macOS)"
    echo "============================================"
    echo ""

    # Check prerequisites
    if ! command -v brew &>/dev/null; then
        echo "ERROR: Homebrew is required. https://brew.sh"
        exit 1
    fi

    # Install llama.cpp if needed
    if ! command -v llama-server &>/dev/null; then
        echo ">> Installing llama.cpp via brew..."
        brew install llama.cpp
    fi
    echo ">> llama-server: $(which llama-server)"

    # Install Pi if needed
    if ! command -v pi &>/dev/null; then
        echo ">> Installing Pi coding agent..."
        npm install -g @earendil-works/pi-coding-agent
    fi
    echo ">> pi: $(which pi)"

    # Download model if needed
    if ! ls models/*.gguf &>/dev/null 2>&1; then
        echo ""
        echo ">> Downloading Qwen 3.6 27B ($QUANT)..."
        QUANT="$QUANT" MTP="$MTP" ./scripts/download-model.sh
    else
        echo ">> Model already downloaded"
    fi

    # Check if already running
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo ""
        echo ">> llama-server already running (PID $(cat "$PID_FILE"))"
    else
        echo ""
        echo ">> Starting llama-server in background..."

        MODEL=$(find models -name "*.gguf" -not -name "model.gguf" -type f | head -1)
        [ -z "$MODEL" ] && MODEL="models/model.gguf"

        MTP_ARGS=""
        if [ "$MTP" = "true" ]; then
            MTP_ARGS="--spec-type mtp --spec-draft-n-max 5 --spec-draft-p-min 0.75"
            echo "   MTP speculative decoding enabled"
        fi

        nohup llama-server \
            -m "$MODEL" \
            -ngl "$NGL" \
            -c "$CTX" \
            -np 1 \
            -fa on \
            --batch-size 2048 \
            --no-mmap \
            --mlock \
            --jinja \
            --metrics \
            --cache-type-k q8_0 \
            --cache-type-v q8_0 \
            --host 127.0.0.1 \
            --port "$PORT" \
            $MTP_ARGS \
            > "$LOG_FILE" 2>&1 &

        echo $! > "$PID_FILE"
        echo "   PID: $(cat "$PID_FILE")"
        echo "   Waiting for model to load..."

        for i in $(seq 1 120); do
            if curl -sf "http://127.0.0.1:${PORT}/health" | grep -q "ok" 2>/dev/null; then
                echo "   Ready."
                break
            fi
            if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                echo "ERROR: llama-server crashed. Check: ./mac-setup.sh logs"
                rm -f "$PID_FILE"
                exit 1
            fi
            if [ "$i" -eq 120 ]; then
                echo "ERROR: Timeout waiting for llama-server. Check: ./mac-setup.sh logs"
                exit 1
            fi
            sleep 1
        done
    fi

    # Detect model ID from server
    MODEL_ID=$(curl -sf "http://127.0.0.1:${PORT}/v1/models" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null \
        || echo "model.gguf")
    echo ">> Detected model ID: $MODEL_ID"

    # Configure Pi for local server
    PI_CONFIG_DIR="${HOME}/.pi/agent"
    mkdir -p "$PI_CONFIG_DIR"
    cat > "$PI_CONFIG_DIR/models.json" << EOF
{
  "providers": {
    "llama-cpp": {
      "baseUrl": "http://127.0.0.1:${PORT}/v1",
      "api": "openai-completions",
      "apiKey": "local",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false
      },
      "models": [
        {
          "id": "${MODEL_ID}",
          "name": "Qwen 3.6 27B (Local)",
          "reasoning": false,
          "input": ["text"],
          "contextWindow": ${CTX},
          "maxTokens": 8192,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
EOF

    echo ""
    echo "============================================"
    echo "  Ready! Server: http://127.0.0.1:${PORT}"
    echo "============================================"
    echo ""
    echo "  Run the demo:"
    echo "    cd demo && pi"
    echo ""
    echo "  Use on any project:"
    echo "    cd /path/to/project && pi"
    echo ""
    echo "  Stop the server:"
    echo "    ./mac-setup.sh stop"
    echo ""
}

do_stop() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID"
            echo ">> llama-server stopped (PID $PID)"
        else
            echo ">> llama-server was not running"
        fi
        rm -f "$PID_FILE"
    else
        echo ">> llama-server is not running"
    fi
}

do_status() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo ">> llama-server running (PID $(cat "$PID_FILE"))"
        curl -sf "http://127.0.0.1:${PORT}/health" 2>/dev/null || echo "   (not ready yet)"
    else
        echo ">> llama-server is not running"
    fi
}

do_logs() {
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo ">> No log file found"
    fi
}

case "${1:-}" in
    start)  do_start ;;
    stop)   do_stop ;;
    status) do_status ;;
    logs)   do_logs ;;
    *)      usage ;;
esac
