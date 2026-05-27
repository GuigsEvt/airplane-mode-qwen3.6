#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env if present
[ -f .env ] && source .env

QUANT="${QUANT:-Q4_K_M}"
MTP="${MTP:-false}"
LLAMA_PORT="${LLAMA_PORT:-8080}"

echo "============================================"
echo "  Airplane Mode - Qwen 3.6 27B Setup"
echo "============================================"
echo ""

# Step 1: Check prerequisites
echo ">> Checking prerequisites..."

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is required. Install from https://docker.com"
    exit 1
fi
echo "   Docker: OK"

if ! command -v huggingface-cli &>/dev/null && ! command -v hf &>/dev/null; then
    echo "ERROR: huggingface-cli is required for model download."
    echo "  pip install huggingface-hub"
    exit 1
fi
echo "   huggingface-cli: OK"
echo ""

# Step 2: Download model (if not already present)
if ls models/*.gguf &>/dev/null 2>&1; then
    echo ">> Model already downloaded:"
    ls -lh models/*.gguf
else
    echo ">> Downloading Qwen 3.6 27B ($QUANT)..."
    QUANT="$QUANT" MTP="$MTP" ./scripts/download-model.sh
fi
echo ""

# Step 3: Start llama-server via Docker
echo ">> Starting llama-server..."
docker compose up -d llama-server
echo "   Waiting for model to load (this can take a minute)..."

for i in $(seq 1 60); do
    if curl -sf "http://127.0.0.1:${LLAMA_PORT}/health" | grep -q "ok" 2>/dev/null; then
        echo "   llama-server is ready on port ${LLAMA_PORT}"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "ERROR: llama-server failed to start. Check: docker compose logs llama-server"
        exit 1
    fi
    sleep 2
done
echo ""

echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "  llama-server: http://127.0.0.1:${LLAMA_PORT}"
echo "  Model: Qwen 3.6 27B ($QUANT)"
echo ""
echo "  Launch Pi coding agent:"
echo "    docker compose run --rm pi"
echo ""
echo "  Then prompt:"
echo "    'Run the tests, find the bugs, and fix them.'"
echo ""
echo "  To stop everything:"
echo "    docker compose down"
echo ""
