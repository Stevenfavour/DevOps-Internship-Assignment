# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### TypeScript Caller Worker
- Install dependencies: `npm install` (run in `workers/caller-worker`)
- Development mode with hot‑reloading: `npm run dev`
- Build for production: `npm run build`
- Run the compiled worker: `node dist/worker.js` (ensure `III_URL` env var points at the III engine or a local instance)

### Python Inference Worker
- Install dependencies: `pip install -r requirements.txt`
- Run the worker: `python inference_worker.py` (set `III_URL` env var if not using default `ws://localhost:49134`)

### III Engine Configuration
- The engine is configured via `config.yaml`. Adjust ports, host, or enable/disable workers as needed.
- Start the engine (if not already running) according to the III documentation (e.g., `iii start` or the appropriate CLI command).

### End‑to‑End Local Development
1. Start the III engine with `config.yaml`.
2. In one terminal, launch the inference worker.
3. In another terminal, launch the caller worker (dev mode or built binary).
4. Send a test request via `curl`:
   ```bash
   curl -X POST http://127.0.0.1:3111/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"messages": [{"role": "user", "content": "Hello!"}]}'
   ```
   The response JSON contains the model output under `result`.

### Running a Single Test
- To exercise the HTTP trigger without the full engine, you can invoke the TypeScript function directly:
  ```bash
  node -e "require('./dist/worker.js').iii.trigger({function_id:'inference::get_response', payload:{messages:[{role:'user',content:'Hi'}]}}).then(console.log)"
  ```
  (Replace paths as appropriate after building.)

## High‑Level Architecture
- **III Engine**: Central orchestrator defined in `config.yaml`. Provides workers, queue, state, observability, and an HTTP gateway.
- **Inference Worker (Python)**: Loads a quantized Gemma‑3‑270M model via HuggingFace `transformers`. Exposes `inference::run_inference` which accepts a `messages` array, applies a chat template, runs generation, and returns the generated text.
- **Caller Worker (TypeScript)**:
  - Registers `inference::get_response` which forwards the incoming payload to the Python worker and augments the response with a static `success` message.
  - Registers an HTTP trigger `http::run_inference_over_http` bound to `POST /v1/chat/completions`. This endpoint extracts the request body, calls `inference::get_response`, and returns a JSON HTTP response.
- **Communication**: Workers communicate over the III RPC protocol (WebSocket). The HTTP worker acts as the public entry point; all other workers remain private within the subnet.
- **State & Observability**: Optional workers (`iii-state`, `iii-observability`) are configured but not used by the sample code. They can be enabled for production debugging or metrics.

## Important Files
- `workers/inference-worker/inference_worker.py` – Python implementation of model loading and inference.
- `workers/caller-worker/src/worker.ts` – TypeScript implementation of RPC client and HTTP trigger.
- `workers/caller-worker/package.json` – npm scripts for dev and build.
- `workers/inference-worker/requirements.txt` – Python dependencies.
- `config.yaml` – III engine configuration, including worker paths and HTTP settings.
- `README.md` (in `quickstart`) – Overview of the prototype and intended usage.

## Cursor / Copilot Rules (if present)
- No explicit Cursor or Copilot rule files were found in this repository.

## Usage Tips for Claude Code
- When asked to run a single test, prefer the `npm run dev` mode for rapid feedback on the TypeScript side and the direct `python` command for the Python worker.
- For full‑stack integration tests, ensure the III engine is running with the `config.yaml` you have edited.
- If a user wants to change the model or quantization, they should edit `model_id` and `gguf_file` in `inference_worker.py` and reinstall dependencies if needed.
- The HTTP endpoint is the only public surface; keep it secured when deploying to cloud (firewall rules, auth tokens, etc.).
