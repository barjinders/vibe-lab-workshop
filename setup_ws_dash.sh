#!/usr/bin/env bash
set -euo pipefail

DEST="."
FORCE=0

usage() {
  cat >&2 <<EOF
Usage: $0 [-d DEST] [-f]
Options:
  -d DEST   Destination directory (default: current)
  -f        Force overwrite existing files
EOF
}

while getopts ":d:fh" opt; do
  case "${opt}" in
    d) DEST="${OPTARG}" ;;
    f) FORCE=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

DEST="$(cd "${DEST}" && pwd)"
mkdir -p "${DEST}/memory-bank" "${DEST}/.clinerules"

# Helper: write file if absent or -f (reads content from stdin)
write_file() {
  local path="$1"
  if [[ ! -f "${path}" || "${FORCE}" -eq 1 ]]; then
    cat > "${path}"
    echo "Wrote: ${path}"
  else
    echo "Exists (skipping): ${path} (use -f to overwrite)"
  fi
}

# ----------------------------
# memory-bank seed documents
# ----------------------------

write_file "${DEST}/memory-bank/activeContext.md" <<'EOF'
# activeContext.md

Current focus:
- Phased workshop build (curl-first)
  1) GET $API_BASE_PATH/recipe minimal
  2) Add POST, /health, /ready
  3) Enforce + parse INGREDIENTS_LIST
  4) Add Woolworths search + LLM
EOF

write_file "${DEST}/memory-bank/projectbrief.md" <<'EOF'
# projectbrief.md

Project: Recipe Generator (FastAPI + Dash) using OCI Generative AI

Goals:
- Generate dinner recipes via OCI GenAI with optional cuisine/dietary preferences
- Parse ingredient list via a strict "INGREDIENTS_LIST:" line for downstream use
- Provide a Dash UI with stateful UX, shopping list, and simple pricing sum
- Integrate Woolworths product search + LLM reasoning for product selection
- Deliver a phased, curl-first workshop flow; hide technicals behind config/rules

Scope:
- Local dev (uvicorn)
- Optional containerization (OCIR)
- Optional OCI deployments: Container Instances, API Gateway, Load Balancer
- Natural-language prompts only for participants (Cline enforces .clinerules)
EOF

write_file "${DEST}/memory-bank/productContext.md" <<'EOF'
# productContext.md

Why:
- Users regularly ask "What's for dinner?" and need quick, tailored recipes.

Problems solved:
- Tailored recipes with ingredients & steps, plus shopping assist via products.

How it should work:
- REST API: $API_BASE_PATH/recipe (GET/POST) returns recipe + metadata (+ ingredients, products)
- Dash UI calls API and presents results; persists state across interactions

UX goals:
- Minimal inputs (cuisine/dietary), one-click generation, clear layout
- Ingredient chips + simple price total
- Health checks + structured logging
EOF

write_file "${DEST}/memory-bank/systemPatterns.md" <<'EOF'
# systemPatterns.md

Architecture:
- FastAPI backend
  - app/main.py: app instance, /health, /ready
  - app/routers/v1.py: GET/POST $API_BASE_PATH/recipe, Pydantic models, error handling
  - app/services/genai_service.py: OCI GenAI client (Instance/Resource Principals)
  - app/services/woolworths_service.py: async search + LLM selection (concurrency guard)
  - app/core/config.py: loads YAML config
  - Structured logging for observability

- Dash frontend
  - app.py: UI, state persistence, API calls, display with chips and pricing

Config-driven:
- All env/IDs/endpoints in workshop-config.yaml or env/secrets
- Default base path: $API_BASE_PATH

Endpoints and contracts:
- GET $API_BASE_PATH/recipe: optional cuisine, dietary; returns { model, cuisine, dietary, recipe, ingredients?, products? }
- POST $API_BASE_PATH/recipe: JSON body {cuisine?, dietary?}; returns same shape
- GET /health, GET /ready (readiness: signer available, endpoint + model ID set)

Recipe response:
- Ends with "INGREDIENTS_LIST: a, b, c" for deterministic parsing.

Structured logging (JSON lines):
- recipe_request_received, recipe_request_success, recipe_request_error
  - Include: method, model, cuisine, dietary
EOF

write_file "${DEST}/memory-bank/techContext.md" <<'EOF'
# techContext.md

Technologies:
- Python 3.10+
- FastAPI, Uvicorn
- Dash, dash-bootstrap-components
- OCI Python SDK (oci) for Generative AI
- YAML config management
- requests (UI client)

Local commands (examples):
- Run API from repo root:
  python3 -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT --reload
- Docs: http://localhost:$API_PORT/docs
- API endpoint: http://localhost:$API_PORT$API_BASE_PATH/recipe

Curl tips:
- Use shell "&" (not HTML-encoded) in query strings.
EOF

write_file "${DEST}/memory-bank/genaiStandards.md" <<'EOF'
# GenAI Service Standard (OCI Python SDK) — Non‑Negotiable

Client:
- oci.generative_ai_inference.GenerativeAiInferenceClient
- signer: InstancePrincipalsSecurityTokenSigner() (or get_resource_principals_signer() in containers)
- service_endpoint from settings.oci.service_endpoint

Chat request (exact):
- GenericChatRequest:
  - messages = [Message(role="USER", content=[TextContent(text=prompt)])]
  - temperature/top_p/max_tokens from settings.llm
- ChatDetails ONLY:
  - compartment_id = settings.oci.compartment_ocid
  - serving_mode = OnDemandServingMode(model_id=settings.llm.model_id)
  - chat_request = the GenericChatRequest

Response:
- Parse from: response.data.chat_response.choices[0].message.content[0].text

Prompt discipline:
- Ensure final line:
  INGREDIENTS_LIST: a, b, c
- Parse deterministically downstream.

Source-of-truth:
- All values from workshop-config.yaml (settings).
EOF

write_file "${DEST}/memory-bank/woolworthsStandards.md" <<'EOF'
# Woolworths Integration Standard — Async Search + LLM-backed Selection

HTTP client:
- httpx.AsyncClient(base_url="https://www.woolworths.com.au/apis", timeout tuned)
- Required browser-like headers (no API key for UI endpoints)

Endpoint:
- GET /ui/Search/products?searchTerm=...

Concurrency/backpressure:
- asyncio.Semaphore controls; retries/backoff; bounded timeouts

Extractor:
- Flatten nested Products wrappers
- Map: displayName, image (prefer LargeImage*, multiple fallbacks), price (parse strings/fields)
- Deduplicate by displayName

Selection:
- For each ingredient, return ONE best candidate with reasoning (LLM) or heuristic fallback
- products: [{ displayName, price?, image?, reasoning? }]

Public async API:
- search_products(term) -> List[dict]
- select_for_ingredients(ingredients) -> List[dict]
EOF

write_file "${DEST}/memory-bank/containerStandards.md" <<'EOF'
# Containerization Standard — Python API and Dash

Images:
- python:3.11-slim
- Non-root, small images, WORKDIR /app
- Healthchecks:
  - API: GET /health
  - UI: HEAD /

Runtime:
- API: uvicorn app.main:app --host 0.0.0.0 --port ${API_PORT:-$API_PORT} --workers ${UVICORN_WORKERS:-2}
- UI: dash app via python app.py --port ${STREAMLIT_PORT:-$STREAMLIT_PORT}

OCIR:
- docker login <region>.ocir.io (Auth Token)
- Tag/push per workshop-config.yaml
EOF

write_file "${DEST}/memory-bank/systemdStandards.md" <<'EOF'
# Systemd Services Standard — API and Dash

Non‑negotiable:
- Two services:
  - recipe-api.service (FastAPI + uvicorn)
  - recipe-dash.service (Dash UI)
- WorkingDirectory = project path
- Restart=always; WantedBy=multi-user.target
- Prefer .venv/bin/python if present
- Absolute paths in unit files; ExecStart via /usr/bin/bash -lc
EOF

write_file "${DEST}/memory-bank/devopsStandards.md" <<'EOF'
# DevOps Standards — Projects, Repositories, Git

- Require Notifications topic for DevOps project
- Hosted repository creation with default branch main
- Prefer SSH, fallback to HTTPS (Auth Token)
- Clean push: add .gitignore; remove temp artifacts; set upstream
- Handle divergent branches with fetch/pull merge (no rebase) then push
EOF

write_file "${DEST}/memory-bank/mcpStandards.md" <<'EOF'
# MCP Server Standards — Local Tooling

Tools:
- get_recipe (GET /recipe), post_recipe (POST /recipe) mirroring the API

Config:
- SERVICE_BASE_URL must match API mounting (root vs /api/v1)

Timeouts:
- 300s timeouts; trim optional args; return clean error text
EOF

write_file "${DEST}/memory-bank/streamlitStandards.md" <<'EOF'
# Streamlit App Standard — Minimal UI (Optional)

- st.set_page_config(title="What's for Dinner?", page_icon="🍽️", layout="wide")
- Sidebar: API Base URL (with Test API), cuisine/dietary selects (+ "Other..." textboxes), actions: Generate (POST) / Surprise me (GET)
- State via st.session_state: api_base_url, last_result, cart
- API client via requests with timeout STREAMLIT_API_TIMEOUT (default 300s):
  - GET/POST {base}/recipe with optional cuisine/dietary
- Main layout:
  - Recipe (title/body), Ingredients (chips -> add to cart), Product suggestions (image, price, reasoning -> add to cart)
  - Debug expander showing raw API JSON
- Reasoning normalization: strip zero-width chars/nbsp, fix spacing; insert "#### Steps" before first numbered step if missing
EOF

write_file "${DEST}/memory-bank/gradioStandards.md" <<'EOF'
# Gradio App Standard — Minimal UI (Optional)

- Blocks(title="What's for Dinner?")
- Sidebar: API base URL, cuisine/dietary, actions
- Center: recipe, ingredients (chips), products (cards), debug JSON
- State + requests client with bounded timeouts
- Prefer gr.update(...) on Gradio 4.x
EOF

write_file "${DEST}/memory-bank/dashStandards.md" <<'EOF'
# Dash Standards — “What’s for Dinner?” (Workshop Memory Bank)

Intent
- Provide a repeatable, copy/paste‑driven way to build the current enterprise Dash UI exactly as delivered.
- Hide technical decisions behind the Memory Bank and .clinerules so natural‑language prompts are sufficient.
- Align Dash behavior with existing workshop patterns (config discovery, run scripts, firewall, health checks).

Authoritative visual + UX contract (must match exactly)
- Theme: dash-bootstrap-components LUX
  - app = Dash(__name__, external_stylesheets=[dbc.themes.LUX])
  - Do NOT load a separate Bootstrap CSS; rely on dbc theme only.
- Hero (top banner):
  - Gradient: linear-gradient(135deg, #0ea5e9 0%, #2563eb 100%)
  - Title centered large; tagline text color rgba(255,255,255,0.95) for readability.
- Page structure (dbc Rows/Cols):
  - Three columns:
    1) Left card: Preferences (cuisine/dietary + actions + API config)
    2) Center column: three stacked cards (Recipe, Ingredients, Product Suggestions)
    3) Right card: Shopping Cart (sticky, position: sticky; top: ~2rem)
- Left card (Preferences) order:
  - “🍴 Your Preferences” header
  - Cuisine select (shows “Custom cuisine” textbox when “Other...” selected)
  - Dietary select (shows “Custom dietary” textbox when “Other...” selected)
  - Primary actions row: “Generate” (POST) and “Surprise me” (GET)
  - API Base URL textbox beneath buttons
  - Test API button + Markdown health output beneath the textbox
- Loading UX (visible feedback):
  - Global: dcc.Loading(fullscreen=True, type="circle") wrapping the entire main content Row.
  - Per‑panel: dcc.Loading around Recipe, Ingredients, Product Suggestions, and Cart.
  - Per‑button: dcc.Loading around Generate and Surprise buttons.
- Cart rendering:
  - One item per line, total shown at the top and updates with each addition.
- Debug panel:
  - Collapsible section at the bottom: “Toggle Debug API Output”, showing raw JSON.

API + behavior
- Config discovery (mirrors workshop-config.yaml defaults):
  - DEFAULT_API_PORT (e.g., 8010), DEFAULT_API_BASE_PATH (e.g., /api/v1)
  - DEFAULT_BASE_URL = http://localhost:${DEFAULT_API_PORT}${DEFAULT_API_BASE_PATH}
  - Environment override: API_BASE_URL (if set).
- Endpoints:
  - POST ${baseUrl}/recipe with optional JSON { cuisine?, dietary? }
  - GET ${baseUrl}/recipe with optional query params
- Expected fields:
  - recipe (text), optional model/cuisine/dietary for caption
  - ingredients: list[str]; renders as chips (buttons); click adds to cart
  - products: list[{ displayName, price?, image?, reasoning? }]; card with image, price, reasoning; click adds to cart
- HTTP utilities (requests, timeout via DASH_API_TIMEOUT default 300s):
  - call_recipe_post(base_url, cuisine?, dietary?) -> dict
  - call_recipe_get(base_url, cuisine?, dietary?) -> dict
  - test_api_health(base_url) -> str (Markdown summary; include JSON when available)

Image normalization (Woolworths UI data)
- prefer_large(url): 
  - // → https://, /content/wowproductimages → https://www.woolworths.com.au
  - Promote /small|/medium/ → /large/

Run story (repeatable)
- recipe-dash-app/requirements.txt: 
  - dash, dash-bootstrap-components, requests
- recipe-dash-app/run.sh behavior:
  - Kills any listeners on 8050/8051
  - Creates/uses .venv-dash
  - pip install -r requirements.txt
  - Launches app on 8050; fallback 8051 if busy (optional)
  - Prints local HEAD check and tails serve.log when available
- recipe-dash-app/allow_firewall.sh behavior:
  - Opens ports 8050/8051 (Dash) and 8010 (FastAPI) using firewalld or iptables
  - Prints local HEAD checks and external URL hints

Dash guides alignment (ensures stability)
- Do not mix CDN Bootstrap with dbc theme; use dbc.themes.LUX only.
- Use dcc.Loading to communicate latency globally, per-panel, and on the critical buttons.
- Use pattern-matching callbacks for dynamic “Add to cart”.
- Keep large CSS in index_string. Do not use app.css.append_css.

Acceptance checklist (copy/paste)
- Launch: bash recipe-dash-app/run.sh
- Open: http://127.0.0.1:8050/
- Validate:
  - Blue hero gradient with white tagline, LUX theme applied
  - Left card order: selects → buttons → API Base URL → Test API/output
  - Generate/Surprise show spinners; global/section spinners visible while loading
  - Recipe/Ingredients/Products cards populate; chips/buttons add to cart
  - Cart displays one item per line; total at the top; sticky in the right column
  - Debug panel toggles raw JSON at bottom

Failure modes + remedies
- Theme looks off: ensure no Bootstrap CDN link; use dbc.themes.LUX only.
- No spinners: verify dcc.Loading wrappers (global and around the four panels) and button-level wrappers.
- Cart shows as a paragraph: ensure Markdown lines joined with “\n” and total printed first.
- API Base URL unknown: edit in the left card textbox and click Test API.

Prompt template (for Dash)
- Supported natural-language prompt (maps to this standard):
  Build a friendly plotly dash app called “What’s for Dinner?” under recipe-dash-app/. Use the Workshop Memory Bank and workshop-config.yaml to handle all the details quietly in the background (per Gradio App Standard). The app should:
  - Let me choose cuisine and dietary options on the left with “Generate” (POST) and “Surprise me” (GET)
  - Show the recipe, clickable ingredient chips (to add to cart), and product suggestions with prices and clear reasons
  - Work out of the box with my running API; if the address isn’t known, let me set it in a textbox and include a quick Test API button
  - Provide a command to run the app (and a backup port if the first is busy)
  - Hide technical choices and implementation details; follow the Memory Bank, configuration, and .clinerules
  - Create or use a virtual env for the dash UI
  - Allow iptables and firewalld for dash and FastAPI ports and verify external access
  - Show a Debug API Output panel at the bottom with the raw JSON response

Implementation cues for agents (hidden detail)
- The exact component structure and wrappers (LUX + hero + loading overlays) must be reproduced verbatim.
- Place API Base URL and Test API strictly below Generate/Surprise.
- Maintain hero gradient colors and tagline contrast values.
- Default recipe-dash-app port 8050; reserve 8051 as fallback (optional).
EOF

# ----------------------------
# Mirror memory-bank -> .clinerules
# ----------------------------
pairs_list="$(cat <<'EOF'
activeContext.md:00-active-context.md
projectbrief.md:01-project-brief.md
systemPatterns.md:02-system-patterns.md
techContext.md:03-tech-context.md
productContext.md:04-product-context.md
genaiStandards.md:05-genai-service-standard.md
woolworthsStandards.md:06-woolworths-service-standard.md
streamlitStandards.md:07-streamlit-app-standard.md
containerStandards.md:08-container-standards.md
systemdStandards.md:09-systemd-services.md
devopsStandards.md:10-devops-standards.md
mcpStandards.md:11-mcp-standards.md
gradioStandards.md:12-gradio-app-standard.md
dashStandards.md:13-dash-app-standard.md
EOF
)"

while IFS=: read -r src dst; do
  [[ -z "$src" || -z "$dst" ]] && continue
  if [[ -f "${DEST}/memory-bank/${src}" ]]; then
    if [[ -f "${DEST}/.clinerules/${dst}" && "${FORCE}" -ne 1 ]]; then
      echo "Exists (skipping): .clinerules/${dst}"
    else
      cp -f "${DEST}/memory-bank/${src}" "${DEST}/.clinerules/${dst}"
      echo "Mirrored: memory-bank/${src} -> .clinerules/${dst}"
    fi
  else
    echo "Warning: missing memory-bank/${src} (skipped)"
  fi
done <<< "$pairs_list"

# ----------------------------
# AGENTS.md aggregation
# ----------------------------
if [[ ! -f "${DEST}/AGENTS.md" || "${FORCE}" -eq 1 ]]; then
  {
    echo "# Workspace Rules (AGENTS.md)"
    echo
    for f in \
      "00-active-context.md" \
      "01-project-brief.md" \
      "02-system-patterns.md" \
      "03-tech-context.md" \
      "04-product-context.md" \
      "05-genai-service-standard.md" \
      "06-woolworths-service-standard.md" \
      "07-streamlit-app-standard.md" \
      "08-container-standards.md" \
      "09-systemd-services.md" \
      "10-devops-standards.md" \
      "11-mcp-standards.md" \
      "12-gradio-app-standard.md" \
      "13-dash-app-standard.md"
    do
      if [[ -f "${DEST}/.clinerules/${f}" ]]; then
        echo "## ${f}"
        echo
        sed -e 's/\r$//' "${DEST}/.clinerules/${f}"
        echo
      fi
    done
  } > "${DEST}/AGENTS.md"
  echo "Wrote: ${DEST}/AGENTS.md"
else
  echo "Exists (skipping): ${DEST}/AGENTS.md (use -f to overwrite)"
fi

# ----------------------------
# workshop-config.yaml (template, private_ip blank by default)
# ----------------------------
write_file "${DEST}/workshop-config.yaml" <<'EOF'
# workshop-config.yaml - Edit with your OCI and project details

oci:
  service_endpoint: "https://inference.generativeai.us-chicago-1.oci.oraclecloud.com"  # adjust to your region
  auth_mode: "instance_principals"
  compartment_ocid: "ocid1.compartment.oc1..xxxxxxxx"

llm:
  model_id: "xai.grok-4-fast-reasoning"
  temperature: 0.7
  top_p: 0.9
  max_tokens: 2000

api:
  base_path: "/api/v1"
  port: 8010

web_interface:
  port: 8051

docker:
  registry: "syd.ocir.io/your-namespace/recipe-api"
  tag: "latest"

deployment:
  container_instance_shape: "CI.Standard.E4.Flex"
  subnet_ocid: "ocid1.subnet.oc1..xxxxxxxx"
  private_ip: ""  # leave blank to auto-assign

api_gateway:
  display_name: "vibe-api-public-gw"
  type: "PUBLIC"
  subnet_id: "ocid1.subnet.oc1..xxxxxxxx"

website_lb:
  display_name: "vibe-workshop-website-lb"
  shape: "flexible"
  is_public: true
  subnet_ids:
    - "ocid1.subnet.oc1..xxxxxxxx"
  listener_port: 80
  backend_host: "localhost"
  backend_port: 8051
  health_check_path: "/"
  health_check_protocol: "HTTP"
  health_check_port: 8051
EOF

# ----------------------------
# recipe-guide.json (prompt-only)
# ----------------------------
write_file "${DEST}/recipe-guide.json" <<'EOF'
{
  "title": "Recipe Workshop - Prompt Guide",
  "overview": "Build step-by-step with prompts. Technical details live in memory-bank/*.md, .clinerules/*.md, and workshop-config.yaml.",
  "phases": [
    {
      "id": "p1",
      "title": "Minimal API: GET endpoint",
      "prompt": "Create a minimal backend API exposing GET /api/v1/recipe returning {recipe:string}. Run on port 8010; provide curl test."
    },
    {
      "id": "p2",
      "title": "Inputs and health",
      "prompt": "Add POST /api/v1/recipe with optional cuisine/dietary, and /health + /ready endpoints. Return {model,cuisine,dietary,recipe}. Use base path from configuration."
    },
    {
      "id": "p3",
      "title": "Enforce and parse ingredients",
      "prompt": "Ensure the recipe text ends with: INGREDIENTS_LIST: a, b, c. Parse into an array 'ingredients' in the API response."
    },
    {
      "id": "p4",
      "title": "Add Woolworths products with LLM reasoning",
      "prompt": "For each ingredient, search products and suggest ONE best product with price/image/reasoning following the Woolworths Integration Standard."
    },
    {
      "id": "p5",
      "title": "Dash UI",
      "prompt": "Create a Dash UI per Dash Standards that calls the API, shows recipe, chips for ingredients, product cards with reasoning, cart, and a debug panel."
    }
  ]
}
EOF


# ----------------------------
# .env defaults (non-secret)
# ----------------------------
write_file "${DEST}/.env" <<'EOF'
# API and UI
API_PORT=8010
API_BASE_PATH=/api/v1

# UI
DASH_API_TIMEOUT=300
EOF

# ----------------------------
# Additional standards appenders (from dashv3)
# ----------------------------

# Append First-Go Learnings (2025-12-08): Config Discovery + Run Modes
# Ensure memory-bank has the latest guidance and mirror into .clinerules so first run works without tweaks.
if [[ -d "${DEST}/memory-bank" ]]; then
  cat >> "${DEST}/memory-bank/systemPatterns.md" << 'EOF'
## Learnings 2025-12-08 — First‑Go Run Modes and Config Discovery

Config discovery (backend):
- The API config loader looks for workshop-config.yaml in this order:
  1) $WORKSHOP_CONFIG_PATH (if set)
  2) /app/config.yaml (containers)
  3) Current working directory and up to 5 parents
  4) The API package file location and up to 5 parents
  5) ./workshop-config.yaml as a final fallback

Implication:
- You can run the API from the repo root:
    .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT
- Or from the recipe-api folder:
    cd recipe-api
    ../.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port $API_PORT
- No extra env is required for local dev in either case.

Run modes:
- Fast verification (skip external product selection):
    WOOL_TOTAL_TIMEOUT=0 .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT
- Reasoning-enabled (bounded timeouts to avoid long waits):
    export WOOL_REASON_MANDATORY=1
    export WOOL_MAX_INGREDIENTS=1
    export WOOL_TOPK=2
    export WOOL_TIMEOUT=6
    export WOOL_PER_ING_TIMEOUT=20
    export WOOL_REASON_TIMEOUT=25
    export WOOL_REASON_CONCURRENCY=1
    export WOOL_REASON_TOPN=2
    export WOOL_TOTAL_TIMEOUT=30
    .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT

Curl tests:
- GET:
    curl -s "http://localhost:$API_PORT$API_BASE_PATH/recipe?cuisine=Mexican&dietary=vegan" | jq
- POST:
    curl -s -X POST "http://localhost:$API_PORT$API_BASE_PATH/recipe" -H "Content-Type: application/json" -d '{"cuisine":"Thai","dietary":"gluten-free"}' | jq

Notes:
- Ensure httpx is installed in the venv (needed for Woolworths integration):
    ./.venv/bin/python -c 'import httpx' 2>/dev/null || ./.venv/bin/pip install httpx
- Use '&' in shell queries, not HTML-encoded '&'.
EOF

  cat >> "${DEST}/memory-bank/techContext.md" << 'EOF'
## Learnings 2025-12-08 — Dev Run Quickstart

- Run from repo root or recipe-api; config discovery is robust (no special env needed).
- Fast mode (skip external products, immediate responses):
    WOOL_TOTAL_TIMEOUT=0 .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT
- Reasoning-enabled (bounded, non-heuristic):
    export WOOL_REASON_MANDATORY=1
    export WOOL_MAX_INGREDIENTS=1
    export WOOL_TOPK=2
    export WOOL_TIMEOUT=6
    export WOOL_PER_ING_TIMEOUT=20
    export WOOL_REASON_TIMEOUT=25
    export WOOL_REASON_CONCURRENCY=1
    export WOOL_REASON_TOPN=2
    export WOOL_TOTAL_TIMEOUT=30
    .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT
- Dependency sanity:
    ./.venv/bin/python -c 'import httpx' 2>/dev/null || ./.venv/bin/pip install httpx
- Curl tests:
    curl -s "http://localhost:$API_PORT$API_BASE_PATH/recipe?cuisine=Mexican&dietary=vegan" | jq
    curl -s -X POST "http://localhost:$API_PORT$API_BASE_PATH/recipe" -H "Content-Type: application/json" -d '{"cuisine":"Thai","dietary":"gluten-free"}' | jq
EOF

  # Mirror updates into .clinerules for immediate enforcement (overwrite to ensure first-go)
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/systemPatterns.md" "${DEST}/.clinerules/02-system-patterns.md" || true
  cp -f "${DEST}/memory-bank/techContext.md" "${DEST}/.clinerules/03-tech-context.md" || true
fi

# Append Woolworths Images/Prices run-mode learnings (2025-12-08)
# Ensure memory-bank has the latest guidance and mirror into .clinerules so first run works without tweaks.
if [[ -d "${DEST}/memory-bank" ]]; then
  cat >> "${DEST}/memory-bank/systemPatterns.md" << 'EOF'
## Learnings 2025-12-08 — Woolworths images/prices and selection mode

- Do NOT run with WOOL_TOTAL_TIMEOUT=0 if you expect real product images/prices. That flag forces reasoning-only fallback and skips external selection.
- Real selection run (bounded timeouts):
  READY_SIGNER_TIMEOUT=0.3 \
  WOOL_REASON_MANDATORY=1 \
  WOOL_MAX_INGREDIENTS=1 \
  WOOL_TOPK=2 \
  WOOL_TIMEOUT=6 \
  WOOL_PER_ING_TIMEOUT=20 \
  WOOL_REASON_TIMEOUT=20 \
  WOOL_TOTAL_TIMEOUT=30 \
  .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT --reload

- Optional: export WOOLWORTHS_STORE_ID=<storeId> to improve price availability.
- Extractor image keys: SmallImageFile, MediumImageFile, LargeImageFile, ImageUrl/imageUrl, Thumbnail/ThumbnailURL, DetailsImagePaths (first).
- Candidate ordering: prefer candidates with image, then with price, then lower price.
- Curl test:
  curl -s -X POST "http://localhost:$API_PORT$API_BASE_PATH/recipe" -H "Content-Type: application/json" -d '{"cuisine":"Mexican","dietary":"vegan"}' | jq '{products: ((.products // []) | .[0:3] | map({displayName, price, image}))}'
EOF

  cat >> "${DEST}/memory-bank/techContext.md" << 'EOF'
## Learnings 2025-12-08 — Real selection vs reasoning-only

- Reasoning-only quick check (no external selection, images/prices may be null by design):
    WOOL_TOTAL_TIMEOUT=0 .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT
- Real selection (images preferred, bounded timeouts):
    READY_SIGNER_TIMEOUT=0.3 \
    WOOL_REASON_MANDATORY=1 \
    WOOL_MAX_INGREDIENTS=1 \
    WOOL_TOPK=2 \
    WOOL_TIMEOUT=6 \
    WOOL_PER_ING_TIMEOUT=20 \
    WOOL_REASON_TIMEOUT=20 \
    WOOL_TOTAL_TIMEOUT=30 \
    .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT --reload
- To improve price fields:
    export WOOLWORTHS_STORE_ID=3024  # example; use your store ID
EOF

  cat >> "${DEST}/memory-bank/woolworthsStandards.md" << 'EOF'
## Learnings 2025-12-08 — Price and image availability

- Images are provided on UI endpoints via fields like SmallImageFile/MediumImageFile/LargeImageFile/ImageUrl/DetailsImagePaths.
- Prices may require a store context; set WOOLWORTHS_STORE_ID to retrieve store-level pricing when available.
- The selector sorts candidates by presence of image first, then price presence, then lower price.
- Do not set WOOL_TOTAL_TIMEOUT=0 when expecting images/prices; that path skips UI selection entirely.
EOF

  # Mirror updates into .clinerules for immediate enforcement (overwrite to ensure first-go)
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/systemPatterns.md" "${DEST}/.clinerules/02-system-patterns.md" || true
  cp -f "${DEST}/memory-bank/techContext.md" "${DEST}/.clinerules/03-tech-context.md" || true
  cp -f "${DEST}/memory-bank/woolworthsStandards.md" "${DEST}/.clinerules/06-woolworths-service-standard.md" || true
fi

# Append Learnings 2025-12-14 — API first-go port hygiene and OCI signer expectation
if [[ -d "${DEST}/memory-bank" ]]; then
  cat >> "${DEST}/memory-bank/systemPatterns.md" << 'EOF'
## Learnings 2025-12-14 — API first-go port hygiene and OCI signer expectation

- Before the first run, free the API port to avoid EADDRINUSE:
  fuser -k $API_PORT/tcp || true
- Launch exactly one uvicorn process (avoid chaining multiple launches in a single line).
- On OCI hosts with Instance Principals configured, GET $API_BASE_PATH/recipe should return HTTP 200 on first try without any LOCAL_FAKE_RECIPE flag.
- Quick checks:
  pgrep -fa uvicorn || true
  ss -ltnp | grep ":$API_PORT" || true
  curl -s "http://localhost:$API_PORT$API_BASE_PATH/recipe" | head -c 200 || true
EOF

  cat >> "${DEST}/memory-bank/techContext.md" << 'EOF'
## Learnings 2025-12-14 — First-go run on OCI with Instance Principals

- This machine has Instance Principals; expect real OCI GenAI responses on first go (HTTP 200).
- Do not set LOCAL_FAKE_RECIPE in normal runs; that flag is only for offline/local testing.
- Port hygiene: if a prior dev server is bound to $API_PORT, free it first:
  fuser -k $API_PORT/tcp || true
- Single-run discipline: prefer a single uvicorn launch command (avoid multi-launch chains that can spawn duplicates).
EOF
fi

# Ensure Woolworths Hardening requirements (2025-12-10) are present and mirrored to .clinerules
if [[ -d "${DEST}/memory-bank" ]]; then
  if ! grep -q "Hardening requirements (2025-12-10)" "${DEST}/memory-bank/woolworthsStandards.md" 2>/dev/null; then
    cat >> "${DEST}/memory-bank/woolworthsStandards.md" << 'EOF'
## Hardening requirements (2025-12-10) — Non-negotiable extractor/selector behavior

These rules prevent first-run null image/price issues and ensure stable product selection.

1) Product flattening — recursive, no early return
- Recursively traverse the entire payload and collect dict nodes that contain ANY of:
  DisplayName, displayName, Name, Description, UnitPrice, Price, ImageUrl, imageUrl, DetailsImagePaths, Images.
- Do NOT stop at the first "Products" array; nested {"Products":[{"Products":[...]}]} wrappers are common.

2) Image normalization and discovery
- Prefer LargeImageFile / LargeImageUrl when present.
- Fallbacks (in order): ImageUrl/imageUrl, MediumImageFile, SmallImageFile/SmallImageUrl, Thumbnail/ThumbnailURL, first from DetailsImagePaths/Images.
- Normalize protocol-relative and site-root paths:
  - //cdn… -> https://cdn…
  - /content/wowproductimages/... -> https://www.woolworths.com.au/content/wowproductimages/…
- Promote small/medium path segments to large (replace /small|/medium/ with /large/).
- Include a recursive image URL finder that accepts http(s), protocol-relative (//), and site-root (/) paths anywhere in the product dict/list.

3) Price parsing — nested and robust
- Accept numeric values or strings such as "$12.00" (strip symbols and commas).
- Scan nested dict/list structures for any of:
  Price, UnitPrice, UnitPriceValue, RetailPrice, CupPrice, InstorePrice, value, amount.
- Treat zero or <= 0 as missing (None). As a last resort, scan the entire product dict.

4) Brand-bucket filtering and candidate gating
- Drop brand-bucket entries: explicit "Brand"/"Brands" and short non-product labels (≤ 2 tokens, no units/keywords, and no digits).
- Keep candidates only if they have either an image OR a numeric price.
- Sort candidates by: has image (desc), has price (desc), then lower price.

5) AU term cleaning additions
- Extend synonyms with:
  - yogurt -> yoghurt
  - ground chicken -> chicken mince
- Maintain existing mappings (capsicum, coriander, spring onion, rocket, beef mince, plain flour, icing sugar, bicarb soda, cornflour, wholemeal, …).

6) Operational requirements for real prices/images
- Do NOT set WOOL_TOTAL_TIMEOUT=0 if you expect images/prices (that path skips selection).
- Set a store context to improve price availability:
  export WOOLWORTHS_STORE_ID=<storeId>
- Recommended bounded run for realistic selection:

  READY_SIGNER_TIMEOUT=0.3 \
  WOOL_REASON_MANDATORY=1 \
  WOOL_MAX_INGREDIENTS=3 \
  WOOL_TOPK=2 \
  WOOL_TIMEOUT=6 \
  WOOL_PER_ING_TIMEOUT=20 \
  WOOL_REASON_TIMEOUT=20 \
  WOOL_REASON_CONCURRENCY=1 \
  WOOL_REASON_TOPN=2 \
  WOOL_TOTAL_TIMEOUT=30 \
  .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port "$API_PORT" --reload

7) Verification snippet (copy/paste)
- GET preview:
  curl -s "http://localhost:$API_PORT$API_BASE_PATH/recipe?cuisine=Mexican&dietary=vegan" \
    | jq '{ingredients_len:(.ingredients|length), products_preview: ((.products // []) | .[0:3] | map({displayName, price, image}))}'
- POST preview:
  curl -s -X POST "http://localhost:$API_PORT$API_BASE_PATH/recipe" -H "Content-Type: application/json" \
    -d '{"cuisine":"Italian","dietary":"vegetarian"}' \
    | jq '{ingredients_len:(.ingredients|length), products_preview: ((.products // []) | .[0:3] | map({displayName, price, image}))}'

## Common pitfalls and triage
- Null price: set WOOLWORTHS_STORE_ID; ensure price parser scans nested structures; treat zero as None.
- Null image: ensure recursive image discovery and URL normalization; promote small/medium to large; require image OR price to pass.
- No products: verify term cleaning (AU synonyms) and ensure flattening recurses through nested Products wrappers.
- Selection skipped: WOOL_TOTAL_TIMEOUT set to 0 (disable for real products).
- Curl queries: ensure shell ampersand (&) is not HTML-encoded (&).
EOF
  fi
  # Mirror hardened woolworths standards into .clinerules unconditionally
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/woolworthsStandards.md" "${DEST}/.clinerules/06-woolworths-service-standard.md" || true
fi

# Append Streamlit UI learnings (2025-12-09): image sizing, deprecations, and 2-column layouts
if [[ -d "${DEST}/memory-bank" ]]; then
  cat >> "${DEST}/memory-bank/streamlitStandards.md" << 'EOF'
## Learnings 2025-12-09 — Streamlit images and layout

Deprecation notice:
- Streamlit is removing use_container_width/use_column_width. Prefer:
  - st.image(..., width='stretch') for container-wide rendering, or
  - A fixed pixel width (e.g., width=360) for consistent card sizing across rows.

Woolworths product images:
- Prefer LargeImage URLs (LargeImageFile/LargeImageUrl) when available. If upstream returns /small/ or /medium/ paths, promote to /large/ before rendering.
- Constrain render size so images don’t dominate the page. Recommended default for product cards: width=360.

Suggestions placement and grid:
- Move the “Suggestions” section to the bottom of the page (below recipe and cart).
- Render product suggestions two cards per row using st.columns(2):
  ```python
  def render_card(idx: int, p: dict) -> None:
      img = prefer_large(p.get("image"))
      if img:
          st.image(img, width=360)
      st.markdown(f"**{p.get('displayName','Product')}**")
      price = p.get("price")
      st.caption(f"Price: {f'${price:.2f}' if isinstance(price,(float,int)) else '—'}")
      reason = normalize_reasoning(p.get("reasoning"))
      if reason:
          with st.expander("Reasoning", expanded=False):
              st.write(reason)
      if st.button("Add to cart", key=f"add_{idx}"):
          st.session_state.cart.append({"name": p.get("displayName") or "Product", "price": price, "image": img, "source": "product"})

  for i in range(0, len(products), 2):
      cols = st.columns(2)
      with cols[0]:
          render_card(i, products[i])
      if i + 1 < len(products):
          with cols[1]:
              render_card(i + 1, products[i + 1])
  ```

Ingredients layout:
- Show ingredient chips in two columns:
  ```python
  cols = st.columns(2)
  for idx, ing in enumerate(ingredients):
      with cols[idx % 2]:
          if st.button(ing, key=f"ing_{idx}"):
              st.session_state.cart.append({"name": ing, "source": "ingredient"})
  ```

Cart placement:
- Keep the cart in the right column of the main layout; suggestions remain at the bottom of the page for a clear reading flow.

Sidebar UX:
- Always include "API Base URL" with a “Test API” button that calls /health (derived from host:port without base path).

Recommended defaults:
- IMAGE_WIDTH_SUGGESTION=360  # adjust for theme/card layout
- Promote /small|/medium to /large in Woolworths image URLs when possible
EOF

  # Mirror updates into .clinerules for enforcement
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/streamlitStandards.md" "${DEST}/.clinerules/07-streamlit-app-standard.md" || true
fi

# Append Dash detailed design contract (2025-12-12) and mirror to .clinerules
if [[ -d "${DEST}/memory-bank" ]]; then
  if ! grep -q "Dash Design — Detailed CSS and Component Contract (2025-12-12)" "${DEST}/memory-bank/dashStandards.md" 2>/dev/null; then
    cat >> "${DEST}/memory-bank/dashStandards.md" << 'EOF'
## Dash Design — Detailed CSS and Component Contract (2025-12-12)

Intent
- Enforce exact visual/theme and component structure so a single natural-language prompt reproduces the enterprise UI without drift.

Fonts and theme CSS
- Load Inter font:
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
- CSS variables and styles (must be present in app.index_string):
  - :root color tokens, body font, container max-width
  - .hero gradient (linear-gradient(135deg, #0ea5e9 0%, #2563eb 100%)), larger title, tagline rgba(255,255,255,0.95)
  - .card rounded corners + hover transform/box-shadow
  - .btn-primary/.btn-secondary styles
  - .section-divider styling
  - .rounded-pill chip style
  - img hover scale, .debug-pre, .cart-item, .cart-total styles

Component IDs and layout (must match)
- Stores: store-cart, store-last, debug-collapse
- Left preferences (in order):
  - "🍴 Your Preferences" header
  - Cuisine: cuisine-sel (Dropdown), cuisine-other (Input shown when "Other...")
  - Dietary: dietary-sel (Dropdown), dietary-other (Input shown when "Other...")
  - Actions row with spinners: generate-btn, surprise-btn
  - API Base URL textbox: api-input
  - Test API button: test-btn, Output markdown test-out
- Center cards:
  - Recipe card: meta-md, title-md, body-md (ensure Steps heading via helper)
  - Ingredients card: ingredients-info, ingredients-buttons
  - Product Suggestions: products-cards (3 cards per row, dbc.Col width=4)
  - Hidden PM anchors: {'type':'dynamic-ing-btn','index':-1}, {'type':'dynamic-prod-btn','index':-1}
- Right sticky cart:
  - cart-md (Markdown), clear-btn button
- Bottom debug:
  - toggle-debug button, debug-collapse-container (dbc.Collapse), debug-json (pre)

Behavioral contracts
- Ensure Steps heading:
  - Insert "#### Steps" before first numbered step if model omitted an explicit heading.
- Product grid:
  - Render 3 cards per row: dbc.Row([dbc.Col(card,width=4), ...])
  - Card content: image (prefer_large), title, price (— if missing), reasoning (normalized) and "Add to cart"
- Ingredient chips:
  - Use className="rounded-pill" and add to cart on click
- Pattern-matching callbacks:
  - Dynamic ingredients/products use allow_duplicate=True where necessary
  - Use callback_context to detect triggered button
- Per-button loaders:
  - Wrap Generate and Surprise me in dcc.Loading(type="circle")
- API controls placement:
  - API Base URL + Test API strictly below action buttons

Run rules (run.sh requirements)
- Kill 8050/8051 if busy before start
- Create/activate .venv-dash; pip install -r requirements.txt
- Set NO_PROXY/no_proxy to "127.0.0.1,localhost,.localhost"
- Select 8050 with fallback to 8051
- Pass --port to app.py
- Print HEAD check after launching

Acceptance checklist
- LUX theme + Inter font loaded; hero gradient visible; three columns with sticky cart
- Generate/Surprise show spinners and then populate recipe/ingredients/products
- Rounded-pill chips and product cards add to cart; cart total updates
- Debug toggle reveals raw JSON at bottom
EOF
    # Mirror into .clinerules for strict enforcement
    mkdir -p "${DEST}/.clinerules"
    cp -f "${DEST}/memory-bank/dashStandards.md" "${DEST}/.clinerules/13-dash-app-standard.md" || true
  fi
fi

# Append Learnings 2025-12-12 — Dash 3.x run API and Callback RCA (idempotent) and mirror to .clinerules
if [[ -d "${DEST}/memory-bank" ]]; then
  if ! grep -q "Learnings 2025-12-12 — Dash 3.x run API and Callback RCA" "${DEST}/memory-bank/dashStandards.md" 2>/dev/null; then
    cat >> "${DEST}/memory-bank/dashStandards.md" << 'EOF'
## Learnings 2025-12-12 — Dash 3.x run API and Callback RCA

Root causes observed
- Dash >= 3 deprecated app.run_server; using it raises ObsoleteAttributeException. Use app.run(host="0.0.0.0", port=...) instead (bind 0.0.0.0 for health checks and LAN tests).
- Multiple callbacks updating the same Output property require allow_duplicate=True to avoid DuplicateCallbackOutput exceptions. This is common when both “Generate” and “Surprise me” update the same components.
- Pattern-matching callbacks:
  - Use dict IDs like {'type':'dynamic-ing-btn','index':i} and read the trigger via callback_context.triggered to find which index was clicked.
  - Prefer html.Button (or dbc.Button) for consistent click semantics with n_clicks; wrap in dcc.Loading for UX only (does not affect callbacks).
- Port hygiene and proxies:
  - Kill 8050/8051 before launching to avoid EADDRINUSE (fuser -k 8050/tcp || true).
  - Set NO_PROXY/no_proxy="127.0.0.1,localhost,.localhost" to prevent corporate proxies hijacking localhost requests.
- API base URL discovery + health:
  - Default to http://localhost:${DEFAULT_API_PORT}${DEFAULT_API_BASE_PATH} from workshop-config.yaml; allow API_BASE_URL env override.
  - Provide a “Test API” button that calls /health (and optionally /ready) on the origin (host:port only), not on the versioned base path.
- Acceptance checks:
  - UI loads with LUX + Inter, hero gradient visible.
  - Buttons trigger callbacks; recipe/ingredients/products populate; Debug JSON toggles.
  - If products are empty on first-go, confirm API run mode (WOOL_TOTAL_TIMEOUT=0 skips product selection by design).

Run rules (Dash 3.x)
- Always call app.run(host="0.0.0.0", port=...) in app.py.
- In run.sh:
  - Create/activate venv, pip install -r requirements.txt
  - Kill 8050/8051 if busy; pick fallback port
  - Export NO_PROXY/no_proxy for localhost
  - Print HTTP HEAD check after starting
EOF
    mkdir -p "${DEST}/.clinerules"
    cp -f "${DEST}/memory-bank/dashStandards.md" "${DEST}/.clinerules/13-dash-app-standard.md" || true
  fi
fi

# Append Gradio learnings (idempotent) and mirror to .clinerules
if [[ -d "${DEST}/memory-bank" ]]; then
  if ! grep -q "Learnings 2025-12-11 — Gradio 4.x" "${DEST}/memory-bank/gradioStandards.md" 2>/dev/null; then
    cat >> "${DEST}/memory-bank/gradioStandards.md" << 'EOF'
## Learnings 2025-12-11 — Gradio 4.x update API, HTML escaping, and UI defaults

- Use gr.update(...) for all component updates. Do NOT use Component.update (e.g., HTML.update/Textbox.update/Button.update).
- Replace gradio.utils.sanitize_html with Python html.escape for safe rendering.
- Default hidden “Add to cart” buttons; reveal only when products are present via gr.update(visible=True).
- Event handlers must align with inputs: use fn=lambda cart, last, i=idx: ..., inputs=[state_cart, state_last].
- Set GRADIO_SERVER_PORT to the selected port and implement IPv4/IPv6-safe busy checks; fall back 7860 → 7861.
- For gradio>=4.44, add compatibility pin in UI requirements: huggingface_hub<1.0 to avoid oauth/import changes.
EOF
  fi
  if ! grep -q "Learnings 2025-12-11 — Gradio First-go RCA" "${DEST}/memory-bank/gradioStandards.md" 2>/dev/null; then
    cat >> "${DEST}/memory-bank/gradioStandards.md" << 'EOF'
## Learnings 2025-12-11 — Gradio First-go RCA and Fixes

Root causes observed
1) API run mode confusion
   - Running the API with WOOL_TOTAL_TIMEOUT=0 is a quick verification mode that intentionally skips Woolworths selection. The UI then shows products: [] by design, which can be misinterpreted as a UI problem.
   - Fix: For real images/prices/reasoning, start the API with bounded selection flags:
     READY_SIGNER_TIMEOUT=0.3 \
     WOOL_REASON_MANDATORY=1 \
     WOOL_MAX_INGREDIENTS=3 \
     WOOL_TOPK=2 \
     WOOL_TIMEOUT=6 \
     WOOL_PER_ING_TIMEOUT=20 \
     WOOL_REASON_TIMEOUT=20 \
     WOOL_REASON_CONCURRENCY=1 \
     WOOL_REASON_TOPN=2 \
     WOOL_TOTAL_TIMEOUT=30

2) Gradio component pitfalls (4.x)
   - Use gr.update(...) exclusively; Component.update(...) methods are not stable in 4.x.
   - For remote product images, prefer embedding as HTML <img> (gr.HTML) vs gr.Image to avoid file-serving edge cases.
   - Disable public sharing for lab runs (share=False).
   - Provide a fallback port (7860 → 7861) and kill existing listeners before launch.
   - Set NO_PROXY/no_proxy to "127.0.0.1,localhost,.localhost" to prevent corporate proxies from hijacking localhost checks.

3) UX clarity
   - Some model outputs omit an explicit "Steps" heading. Insert a UI-side "Steps" heading before the first numbered step to separate ingredients from instructions without altering the API payload.

4) Compatibility pins
   - Pin gradio>=4.44.1,<4.45.0 and huggingface_hub<1.0 to avoid oauth/import changes.

Quick prompts

- Reasoning-enabled API (bounded selection):
  ```bash
  READY_SIGNER_TIMEOUT=0.3 \
  WOOL_REASON_MANDATORY=1 \
  WOOL_MAX_INGREDIENTS=3 \
  WOOL_TOPK=2 \
  WOOL_TIMEOUT=6 \
  WOOL_PER_ING_TIMEOUT=20 \
  WOOL_REASON_TIMEOUT=20 \
  WOOL_REASON_CONCURRENCY=1 \
  WOOL_REASON_TOPN=2 \
  WOOL_TOTAL_TIMEOUT=30 \
  .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port ${API_PORT:-8010} --reload
  ```

- Gradio UI (venv-first, kill 7860/7861, fallback, no share):
  ```bash
  export API_BASE_URL="http://localhost:${API_PORT:-8010}${API_BASE_PATH:-/api/v1}"
  export NO_PROXY="127.0.0.1,localhost,.localhost"
  export no_proxy="127.0.0.1,localhost,.localhost"
  bash recipe-gradio-app/run.sh
  ```

Checklist (first-go)
- API returns products with reasoning (not in quick mode).
- UI “Test API” returns healthy.
- “Ingredients” chips present; “Suggestions” show images/prices/reasoning.
- Recipe body displays “#### Steps” before numbered instructions if the model omitted a heading.
EOF
  fi
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/gradioStandards.md" "${DEST}/.clinerules/12-gradio-app-standard.md" || true
fi

# Append Systemd Quick Setup (2025-12-09): concise prompt to create/enable/start services (and mirror)
if [[ -d "${DEST}/memory-bank" ]]; then
  cat >> "${DEST}/memory-bank/systemdStandards.md" << 'EOF'
## Quick Setup (2025-12-09) — Systemd services for API and Streamlit (Oracle Linux)

Friendly prompt (copy/paste). Uses your current project directory as WorkingDirectory, prefers .venv if present, starts on boot, and restarts on failure.

```bash
# 1) Set project path and default ports
export PROJECT_DIR="$(pwd)"
export API_PORT="${API_PORT:-8010}"
export STREAMLIT_PORT="${STREAMLIT_PORT:-8501}"

# 2) Create unit: recipe-api.service (FastAPI via uvicorn)
sudo tee /etc/systemd/system/recipe-api.service >/dev/null <<'UNIT'
[Unit]
Description=Recipe API (FastAPI / uvicorn)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=opc
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=-$PROJECT_DIR/.env
Environment=API_PORT=${API_PORT}
Environment=UVICORN_WORKERS=2
ExecStart=/usr/bin/bash -lc 'PY=$([ -x .venv/bin/python ] && echo .venv/bin/python || command -v python3); exec "$PY" -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port "${API_PORT:-8010}" --workers "${UVICORN_WORKERS:-2}"'
Restart=always
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
UNIT

# 3) Create unit: recipe-streamlit.service (Streamlit UI)
sudo tee /etc/systemd/system/recipe-streamlit.service >/dev/null <<'UNIT'
[Unit]
Description=Recipe Streamlit UI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=opc
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=-$PROJECT_DIR/.env
Environment=STREAMLIT_PORT=${STREAMLIT_PORT}
ExecStart=/usr/bin/bash -lc 'PY=$([ -x recipe-streamlit-app/.venv-ui/bin/python ] && echo recipe-streamlit-app/.venv-ui/bin/python || command -v python3); exec "$PY" -m streamlit run recipe-streamlit-app/app.py --server.port="${STREAMLIT_PORT:-8501}" --server.headless=true'
Restart=always
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
UNIT

# 4) Reload, enable on boot, stop any dev listeners, and start services
sudo systemctl daemon-reload
sudo systemctl enable recipe-api.service recipe-streamlit.service
sudo fuser -k "${API_PORT}"/tcp >/dev/null 2>&1 || true
sudo fuser -k "${STREAMLIT_PORT}"/tcp >/dev/null 2>&1 || true
sudo systemctl start recipe-api.service
sudo systemctl start recipe-streamlit.service

# 5) Verify and tail logs
systemctl status --no-pager recipe-api.service
systemctl status --no-pager recipe-streamlit.service
sudo journalctl -u recipe-api.service -f
# In another shell:
sudo journalctl -u recipe-streamlit.service -f
```

Notes
- ExecStart auto-detects a Python venv if present (.venv for API, recipe-streamlit-app/.venv-ui for UI).
- WorkingDirectory is your current project folder; edit the units if you move the project.
- Restart=always and WantedBy=multi-user.target are set to start on boot and auto-restart on failure.
EOF

  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/systemdStandards.md" "${DEST}/.clinerules/09-systemd-services.md" || true
fi

# ----------------------------
# Verify presence
# ----------------------------
verify_rules() {
  echo "Verifying Memory Bank and .clinerules..."
  local mb_dir="${DEST}/memory-bank"
  local cl_dir="${DEST}/.clinerules"

  local mb_required="activeContext.md projectbrief.md systemPatterns.md techContext.md productContext.md genaiStandards.md woolworthsStandards.md streamlitStandards.md containerStandards.md systemdStandards.md devopsStandards.md mcpStandards.md gradioStandards.md dashStandards.md"
  local cl_required="00-active-context.md 01-project-brief.md 02-system-patterns.md 03-tech-context.md 04-product-context.md 05-genai-service-standard.md 06-woolworths-service-standard.md 07-streamlit-app-standard.md 08-container-standards.md 09-systemd-services.md 10-devops-standards.md 11-mcp-standards.md 12-gradio-app-standard.md 13-dash-app-standard.md"

  local count_mb=0; local total_mb=0; local missing_mb=""
  for f in $mb_required; do
    total_mb=$((total_mb+1))
    if [[ -f "${mb_dir}/${f}" ]]; then
      count_mb=$((count_mb+1))
    else
      missing_mb="${missing_mb} ${f}"
    fi
  done

  local count_cl=0; local total_cl=0; local missing_cl=""
  for f in $cl_required; do
    total_cl=$((total_cl+1))
    if [[ -f "${cl_dir}/${f}" ]]; then
      count_cl=$((count_cl+1))
    else
      missing_cl="${missing_cl} ${f}"
    fi
  done

  echo "Memory Bank files: ${count_mb}/${total_mb}"
  [[ -n "${missing_mb// }" ]] && echo "Missing memory-bank files:${missing_mb}"
  echo ".clinerules files: ${count_cl}/${total_cl}"
  [[ -n "${missing_cl// }" ]] && echo "Missing .clinerules files:${missing_cl}"
}

verify_rules
echo "Workshop scaffolding complete."
