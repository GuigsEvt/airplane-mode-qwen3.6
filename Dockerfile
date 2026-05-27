FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv git curl \
    && rm -rf /var/lib/apt/lists/*

# Install Pi coding agent
RUN npm install -g @earendil-works/pi-coding-agent

# Install pytest for the demo
RUN python3 -m pip install pytest --break-system-packages

# Configure Pi to use local llama-server via OpenAI-compatible API
RUN mkdir -p /root/.pi/agent
COPY config/models.json /root/.pi/agent/models.json

WORKDIR /workspace

ENTRYPOINT ["pi"]
