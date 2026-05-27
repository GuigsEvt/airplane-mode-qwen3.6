#!/usr/bin/env bash
set -euo pipefail

# Download Qwen 3.6 27B GGUF model from HuggingFace
# Default: Q4_K_M (17GB) -- good balance of quality/speed/size
# Optional: Q8 or MTP variants for power users

MODELS_DIR="${MODELS_DIR:-$(dirname "$0")/../models}"
REPO="${HF_REPO:-unsloth/Qwen3.6-27B-GGUF}"
QUANT="${QUANT:-Q4_K_M}"
MTP="${MTP:-false}"

# MTP variant for ~2x throughput (requires newer llama.cpp)
if [ "$MTP" = "true" ]; then
    REPO="unsloth/Qwen3.6-27B-MTP-GGUF"
    echo ">> Using MTP variant (Multi-Token Prediction) for ~2x throughput"
fi

mkdir -p "$MODELS_DIR"

echo ">> Downloading Qwen 3.6 27B ($QUANT) from $REPO"
echo ">> Target: $MODELS_DIR"
echo ""

# Check for huggingface-cli
if command -v huggingface-cli &>/dev/null; then
    huggingface-cli download "$REPO" \
        --include "*${QUANT}*" \
        --local-dir "$MODELS_DIR"
else
    echo "huggingface-cli not found. Install with:"
    echo "  pip install huggingface-hub"
    echo ""
    echo "Or download manually from: https://huggingface.co/$REPO"
    exit 1
fi

echo ""
echo ">> Download complete. Model files in: $MODELS_DIR"
ls -lh "$MODELS_DIR"/*.gguf 2>/dev/null || true

# Create a symlink so docker-compose can find the model as model.gguf
GGUF_FILE=$(find "$MODELS_DIR" -name "*.gguf" -type f | head -1)
if [ -n "$GGUF_FILE" ] && [ ! -e "$MODELS_DIR/model.gguf" ]; then
    ln -sf "$(basename "$GGUF_FILE")" "$MODELS_DIR/model.gguf"
    echo ">> Symlinked: model.gguf -> $(basename "$GGUF_FILE")"
fi
