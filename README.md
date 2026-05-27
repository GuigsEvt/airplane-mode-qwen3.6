# Airplane Mode: Local AI Coding Agent

Run a fully local coding agent powered by **Qwen 3.6 27B** -- no API keys, no internet required after setup.

<video src="https://github.com/GuigsEvt/airplane-mode-qwen3.6/raw/main/demo.mov" controls width="100%"></video>

## What This Is

A turnkey setup to run an AI coding agent 100% locally:

- **[llama.cpp](https://github.com/ggml-org/llama.cpp)** serves the Qwen 3.6 27B model with GPU acceleration
- **[Pi coding agent](https://github.com/earendil-works/pi)** (open-source Claude Code alternative) provides the agentic coding interface
- A **demo coding challenge** lets you see it solve real bugs on camera

Everything runs on your machine. No cloud. No API keys. Full airplane mode.

## How It Works

```
You <---> Pi (coding agent) <---> llama-server <---> Qwen 3.6 27B (GGUF)
              |                        |
         reads/edits code        runs on GPU
         runs tests              via Metal (Mac)
         executes bash           or CUDA (Linux)
```

Pi is a terminal-based coding agent with 4 core tools: Read, Write, Edit, Bash. It connects to llama-server via the OpenAI-compatible API. The model runs locally using llama.cpp with full GPU offload.

## Hardware Requirements

| RAM | Recommended Quantization | Model Size | Notes |
|-----|--------------------------|------------|-------|
| 16 GB | Q3_K_M | ~14 GB | Tight -- leave headroom for KV cache |
| 24 GB | Q4_K_M (default) | ~17 GB | Best quality/speed tradeoff |
| 32 GB+ | Q5_K_M / Q6_K | ~20-26 GB | Noticeably better quality |
| 64 GB+ | Q8_0 | ~29 GB | Near-lossless quantization |

Apple Silicon (M1/M2/M3/M4) or Linux with NVIDIA GPU. The model must fit in memory.

---

## macOS Setup (Apple Silicon)

Native setup using Metal GPU acceleration for best performance. Docker cannot access Metal on macOS, so the server runs natively.

### Prerequisites

- **Homebrew**: [brew.sh](https://brew.sh)
- **Node.js**: `brew install node` (for Pi agent)
- **huggingface-cli**: `pip install huggingface-hub` (for model download)

llama.cpp is installed automatically by the setup script.

### Quick Start

```bash
git clone https://github.com/GuigsEvt/airplane-mode-qwen3.6.git
cd airplane-mode-qwen3.6

# Download model, start server, install Pi -- all in one
./mac-setup.sh start
```

The setup script will:
1. Install `llama-server` via Homebrew (if not present)
2. Install Pi coding agent via npm (if not present)
3. Download the Qwen 3.6 27B Q4_K_M GGUF (~17 GB) from HuggingFace
4. Start llama-server in the background with optimized flags (flash attention, mlock, etc.)
5. Auto-detect the model ID and configure Pi to use it

Once it prints "Ready", run the demo:

```bash
cd demo && pi
```

### Server Management

```bash
./mac-setup.sh start     # Start everything (idempotent)
./mac-setup.sh stop      # Stop the llama-server
./mac-setup.sh status    # Check if server is running
./mac-setup.sh logs      # Tail server logs
```

### Monitoring

Open a second terminal while Pi is working:

```bash
./monitor.sh
```

Shows:
- Machine info (chip, cores, RAM)
- Model name and server URL
- Live status (IDLE / GENERATING)
- Real-time tokens/second (generation + prompt processing)
- CPU and memory usage
- Completed run summaries with average tok/s

### Using Pi on Any Project

Pi isn't limited to the demo. Point it at any codebase:

```bash
cd /path/to/your/project && pi
```

---

## Linux Setup (Docker + NVIDIA GPU)

Everything runs in Docker containers -- llama-server and Pi both containerized. The GGUF model is mounted as a volume (not baked into the image).

### Prerequisites

- **Docker** with Docker Compose
- **huggingface-cli**: `pip install huggingface-hub` (for model download)
- **NVIDIA GPU** with [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) (recommended)

### Quick Start

```bash
git clone https://github.com/GuigsEvt/airplane-mode-qwen3.6.git
cd airplane-mode-qwen3.6

# Download the model (~17 GB)
./scripts/download-model.sh

# Start llama-server in background
docker compose up -d llama-server

# Wait for model to load, then launch Pi
docker compose run --rm pi
```

### NVIDIA GPU Support

Uncomment the `deploy` section in `docker-compose.yml`:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

### Using Pi on Your Own Projects

Mount your project directory as the workspace:

```bash
docker compose run --rm -v /path/to/your/project:/workspace pi
```

### Stopping

```bash
docker compose down
```

---

## The Demo

The `demo/` directory contains a small Python project -- a markdown link checker -- with **3 intentional bugs** and a test suite (8 tests: 5 pass, 3 fail).

Prompt Pi with:

```
Run the tests, find the bugs, and fix them.
```

Pi will:
1. Explore the project structure
2. Run `pytest` and see 3 failures
3. Read the source code, diagnose each bug
4. Fix them one by one
5. Re-run tests until all 8 pass

The three bugs:
- **Bug 1**: Anchor link detection checks for `/` instead of `#`
- **Bug 2**: Relative path resolution ignores the base directory
- **Bug 3**: `check_file()` returns all links instead of only issues

---

## Configuration

Optionally customize settings:

```bash
cp .env.example .env
```

| Variable | Default | Description |
|----------|---------|-------------|
| `QUANT` | `Q4_K_M` | GGUF quantization (Q3_K_M, Q4_K_M, Q5_K_M, Q8_0, etc.) |
| `MTP` | `false` | Multi-Token Prediction variant (~2x generation speed) |
| `MODEL_FILE` | `model.gguf` | GGUF filename in `models/` (Docker only) |
| `LLAMA_PORT` | `8080` | llama-server port |
| `LLAMA_CTX` | `32768` | Context window (up to 262144 for this model) |
| `GPU_LAYERS` | `99` | GPU layers to offload (99 = all) |

### Choosing a Quantization

```bash
# Default (~17 GB)
./scripts/download-model.sh

# Higher quality
QUANT=Q8_0 ./scripts/download-model.sh

# MTP variant for faster generation
MTP=true ./scripts/download-model.sh
```

---

## Project Structure

```
.
├── mac-setup.sh             # macOS: start/stop/status/logs (native Metal)
├── monitor.sh               # Live monitoring dashboard
├── docker-compose.yml       # Linux: llama-server + Pi containers
├── Dockerfile               # Pi agent Docker image (Node + Python + Pi)
├── setup.sh                 # Linux: one-command setup
├── .env.example             # Configuration template
├── scripts/
│   └── download-model.sh    # Downloads GGUF from HuggingFace
├── config/
│   └── models.json          # Pi provider config (Docker networking)
├── demo/
│   ├── README.md            # Demo challenge description
│   └── src/
│       ├── link_checker.py      # Buggy code (3 bugs)
│       └── test_link_checker.py # Tests that expose the bugs
└── models/                  # Downloaded GGUF files (gitignored)
```

## Why This Matters

- **No API costs** -- run unlimited requests for free
- **No internet** -- works on a plane, in a bunker, wherever
- **Full privacy** -- your code never leaves your machine
- **No vendor lock-in** -- no rate limits, no ToS changes, no deprecations
- **Sovereignty** -- you own the entire stack

## Credits

- [Qwen 3.6 27B](https://huggingface.co/Qwen/Qwen3.6-27B) by Alibaba
- [Pi coding agent](https://github.com/earendil-works/pi) by Mario Zechner
- [llama.cpp](https://github.com/ggml-org/llama.cpp) by Georgi Gerganov
- [Unsloth GGUF quants](https://huggingface.co/unsloth/Qwen3.6-27B-GGUF)
- Inspired by [Julien Chaumond](https://x.com/julien_c/status/2047647522173104145) (HuggingFace CTO)
