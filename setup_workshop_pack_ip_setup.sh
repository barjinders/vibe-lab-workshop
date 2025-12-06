#!/usr/bin/env bash
#
# setup_workshop_pack.sh
# One-shot script to scaffold the Workshop Memory Bank, workshop-config, and ancillary docs only.
#
# Primary change (2025-11-18):
# - Remove application scaffolding (recipe-api), venv creation, dependency installs, and server startup.
# - Script now ONLY prepares:
#     - memory-bank/*.md
#     - workshop-config.yaml
#     - recipe-guide.json (prompt-only guide for participants)
# - The application is intentionally NOT created by this script. It must be built by users
#   from scratch using the prompts contained in recipe-guide.json, while technical guidance
#   is encoded in memory-bank/*.md and workshop-config.yaml.
#
# Updates (2025-11-25):
# - Removed woolworths/ folder scaffolding and any Postman collection — not required for the workshop.
# - Removed API key references; Woolworths UI endpoints work without auth.
# - Retired the '-r' runner helper; this script no longer generates run_streamlit.sh.
#
# Updates (2025-12-03):
# - Switched all templates to Instance/Resource Principals authentication (no ~/.oci/config).
# - workshop-config.yaml now uses oci.auth_mode: "instance_principals" (no oci.config_path).
# - Memory bank and .clinerules content mirror updated signer-based GenAI client and readiness checks.
#
# Usage:
#   chmod +x ./setup_workshop_pack.sh
#   ./setup_workshop_pack.sh                      # write into current directory, skip existing files
#   ./setup_workshop_pack.sh -f                   # force overwrite existing files
#   ./setup_workshop_pack.sh -d /path/to/project  # write into a different directory
#   ./setup_workshop_pack.sh -d /path -f          # write and overwrite there
#
# Creates (if absent or with -f):
#   ./memory-bank/{projectbrief.md,productContext.md,systemPatterns.md,techContext.md,activeContext.md,genaiStandards.md,woolworthsStandards.md,streamlitStandards.md,containerStandards.md,systemdStandards.md,devopsStandards.md,mcpStandards.md}
#   ./.clinerules/{00-active-context.md,01-project-brief.md,02-system-patterns.md,03-tech-context.md,04-product-context.md,05-genai-service-standard.md,06-woolworths-service-standard.md,07-streamlit-app-standard.md,08-container-standards.md,09-systemd-services.md,10-devops-standards.md,11-mcp-standards.md}
#   ./AGENTS.md (aggregated fallback rules; optional but recommended)
#   ./workshop-config.yaml (template placeholders)
#   ./recipe-guide.json (high-level prompt guide for users)
#
# Notes:
# - Edit workshop-config.yaml to set real OCIDs, namespaces, subnets, etc.
# - Do NOT hardcode secrets. Use env vars or platform secret stores.
# - Cline automatically processes workspace rules in .clinerules/ and detects AGENTS.md in the workspace root.
#   This script mirrors memory-bank/*.md into .clinerules/ so rules are auto-applied by Cline.
# - This script does not generate or run any application code.

set -euo pipefail

# Guard against unbound $1 in unquoted heredocs on shells with 'set -u'
if [ $# -eq 0 ]; then
  set -- ""
fi

# ----------------------------------------------------------------------
# Oracle API Gateway and Container Instance Best Practice (2025-11-30)
# ----------------------------------------------------------------------
# 1. All automation MUST read backend routes, subnets, private IPs, and config ONLY from workshop-config.yaml,
#    memory bank, or .clinerules—never hardcode 10.x addresses or ask user for IP/subnet.
# 2. When containerizing on OCI, always use resource principal for OCI Python SDK authentication
#    as the default unless explicit config is required for local/dev testing.
# 3. Every container instance CLI command (create, update) populates env, subnets, shape, and image url
#    from fully config-driven or standards-driven settings. No values should be set via user prompt.
# 4. Container image registry/push is always tenancy-wide in OCIR. No container registry is "per-compartment".
# 5. On container (re)deploy, always enforce delete-before-recreate if private IP is reused.
# 6. All non-interactive/test runs/demos must configure gateway and backend so that API requests (GET/POST/health)
#    work identically via both localhost and public endpoints. All standards should live in .clinerules/memory-bank.
# 
# Optional (20-30 min): Containerize apps and push to OCIR (devops-recipe standard)
# Optional (20-30 min): Run on OCI Container Instances (API)
# These steps should "just work" with copy/paste and config/memory-bank-driven automation, with no manual troubleshooting required.
# ----------------------------------------------------------------------
# Other previously specified standards (Docker, FastAPI, systemd, etc) still apply.

# Ensure PyYAML is installed for parsing
if ! python3 -c "import yaml" &> /dev/null; then
  echo "Installing pyyaml for YAML parsing..."
  python3 -m pip install pyyaml
fi

DEST="."
FORCE=0

while getopts ":d:f" opt; do
  case "${opt}" in
    d) DEST="${OPTARG}" ;;
    f) FORCE=1 ;;
    *) ;;
  esac
done

# Normalize DEST to absolute path
DEST="$(cd "${DEST}" && pwd)"

echo "Scaffolding Workshop Pack into: ${DEST}"
echo "Force overwrite: ${FORCE}"
echo "---------------------------------------------"

# Load defaults from workshop-config.yaml if it exists (or use hard-coded)
load_defaults() {
  if [ -f "${DEST}/workshop-config.yaml" ]; then
    eval "$(python3 - <<'EOF'
import yaml
import sys
try:
    with open('${DEST}/workshop-config.yaml', 'r') as f:
        config = yaml.safe_load(f)
    print(f"export OCI_SERVICE_ENDPOINT='{config['oci']['service_endpoint']}'")
    print(f"export OCI_AUTH_MODE='{config['oci'].get('auth_mode','instance_principals')}'")
    print(f"export OCI_COMPARTMENT_OCID='{config['oci']['compartment_ocid']}'")
    print(f"export LLM_MODEL_ID='{config['llm']['model_id']}'")
    print(f"export LLM_TEMPERATURE={config['llm']['temperature']}")
    print(f"export LLM_TOP_P={config['llm']['top_p']}")
    print(f"export LLM_MAX_TOKENS={config['llm']['max_tokens']}")
    print(f"export API_BASE_PATH='{config['api']['base_path']}'")
    print(f"export API_PORT={config['api']['port']}")
    print(f"export STREAMLIT_PORT={config['streamlit']['port']}")
    print(f"export DOCKER_REGISTRY='{config['docker']['registry']}'")
    print(f"export DOCKER_TAG='{config['docker']['tag']}'")
except KeyError as ke:
    sys.stderr.write(f"Missing key in YAML: {ke}\n")
except Exception as e:
    sys.stderr.write(f"Error loading YAML: {e}\n")
    print("# workshop-config.yaml error; no defaults exported. Populate workshop-config.yaml and re-run.")
EOF
)"
  else
    echo "workshop-config.yaml not found in ${DEST}. A template will be created; populate it and re-run. No defaults exported."
    # No hard-coded defaults exported when YAML is missing.
  fi
}

# Call to load defaults before scaffolding
load_defaults

# Informational readiness hints (non-fatal)
if [[ -n "${VERBOSE:-}" ]]; then
  echo "Auth mode: ${OCI_AUTH_MODE:-instance_principals} (services should use Instance/Resource Principals; readiness reports signer_available)"
fi

mkdir -p "${DEST}/memory-bank"

# -----------------------------------------------------------------------------
# Memory Bank files (use loaded defaults where applicable)
# -----------------------------------------------------------------------------

# memory-bank/projectbrief.md
if [[ ! -f "${DEST}/memory-bank/projectbrief.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/projectbrief.md" << 'EOF'
# projectbrief.md

Project: Recipe Generator (FastAPI + Streamlit) using OCI Generative AI

Goals:
- Generate dinner recipes via OCI GenAI with optional cuisine/dietary preferences
- Parse ingredient list via a strict "INGREDIENTS_LIST:" line for downstream use
- Provide Streamlit UI with stateful UX, shopping list, and simple pricing sum
- Integrate Woolworths product search + LLM reasoning for product selection
- Deliver a phased, curl-first workshop flow (build GET, then POST/health, etc.)
- Hide all technical details behind workshop-config.yaml and Memory Bank rules

Scope:
- Local dev (uvicorn/streamlit)
- Containerization (Docker), push to OCIR
- OCI deployments: Container Instances (API & Streamlit), API Gateway, Load Balancer
- Natural-language prompts only for participants; Cline uses this Memory Bank and config

Learnings from Phase 1:
- Minimal FastAPI implementation with $API_BASE_PATH/recipe GET endpoint
- OCI GenAI integration using chat API:
  - Use ChatDetails(compartment_id, serving_mode=OnDemandServingMode(model_id), chat_request=GenericChatRequest(...))
  - Put messages/temperature/top_p/max_tokens on GenericChatRequest
  - Do NOT pass messages or inference_params directly to ChatDetails
- Config-driven: loads from workshop-config.yaml; keep OCI endpoint, compartment, and model params out of code
- Simple hardcoded prompt for random dinner recipe
- Local run: python3 -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT --reload
- Verified with curl: returns structured JSON with recipe text
EOF
  echo "Wrote: ${DEST}/memory-bank/projectbrief.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/projectbrief.md (use -f to overwrite)"
fi

# memory-bank/productContext.md
if [[ ! -f "${DEST}/memory-bank/productContext.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/productContext.md" << 'EOF'
# productContext.md

Why:
- Users regularly ask "What's for dinner?" and need quick, tailored recipes

Problems solved:
- Quickly generate coherent recipes with ingredients & steps, tailored to preferences
- Provide a shopping assist via Woolworths product search + LLM reasoning for product selection

How it should work:
- REST API: $API_BASE_PATH/recipe (GET/POST) returns recipe + metadata (+ ingredients, products)
- Streamlit UI calls API and presents results; persists state across interactions
- Deployment via OCI with standard patterns (containers, API Gateway, LB)

User experience goals:
- Minimal inputs (cuisine/dietary), one-click generation, clear result layout
- Visible ingredients chips and a simple price sum
- Stable performance with clear error messages and health checks

Learnings from Phase 1:
- GET $API_BASE_PATH/recipe successfully generates random dinner recipes using OCI GenAI ($LLM_MODEL_ID)
- Response is simple JSON {"recipe": "text"}; future phases will add structured fields like ingredients, products
- Prompt engineering key: hardcoded simple prompt works for basic generation; memory-bank can store advanced templates
EOF
  echo "Wrote: ${DEST}/memory-bank/productContext.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/productContext.md (use -f to overwrite)"
fi

# memory-bank/systemPatterns.md
if [[ ! -f "${DEST}/memory-bank/systemPatterns.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/systemPatterns.md" << 'EOF'
# systemPatterns.md

Architecture:
- FastAPI backend
  - app/main.py: app instance, /health, /ready
  - app/routers/v1.py: GET/POST $API_BASE_PATH/recipe, Pydantic models, error handling
  - app/services/genai_service.py: OCI GenAI client (instance/resource principals signer; no config file)
  - app/services/woolworths_service.py: async search + LLM selection (concurrency guard)
  - app/core/config.py: loads YAML config (use /app/config.yaml in container, local path otherwise)
  - Structured logging for observability
- Streamlit frontend
  - app.py: UI, state persistence (st.session_state), API calls, display with chips and pricing
- Config-driven: All env/IDs/endpoints in workshop-config.yaml or env/secrets
- Deployment topology:
  - Build/push images to OCIR
  - OCI Container Instances for API and Streamlit
  - API Gateway in front of API
  - OCI Load Balancer in front of Streamlit

Operational rules:
1) OCI Container Instances – Private IP reuse
   - Delete existing CI before recreating with same private IP (409 conflict otherwise)
   - Use --wait-for-state SUCCEEDED and regenerate CLI JSON payloads when CLI versions change
2) Streamlit Stateful UI
   - Persist last_result and cart in st.session_state; always render from session
3) GenAI Compartment Rule (containers)
   - Resolve compartment_id robustly:
     1) Provided compartment id
     2) COMPARTMENT_ID env var
     3) signer.get_claim("res_tenant")
4) Concurrency/Performance
   - Async HTTP with concurrency limit (semaphore), retries/backoff, cache common selections

Endpoints and contracts:
- GET $API_BASE_PATH/recipe: optional query cuisine, dietary; returns { model, cuisine, dietary, recipe }
- POST $API_BASE_PATH/recipe: JSON body {cuisine?, dietary?}; returns same shape
- GET /health: { status, service, version }
- GET /ready: { ready: bool, checks: { signer_available, service_endpoint set, model_id_set }, service, version }
- Recipe response ends with "INGREDIENTS_LIST: a, b, c" for deterministic parsing
- Ingredient processing cap: process only the first 5 ingredients by default (configurable via WOOL_MAX_INGREDIENTS)

Structured logging:
- JSON lines to stdout with event keys:
  - recipe_request_received, recipe_request_success, recipe_request_error
- Include fields: method, model, cuisine, dietary

Curl usage:
- Use the configured base path from workshop-config.yaml (default $API_BASE_PATH)
- In shells, use & (ampersand) in query strings; do not paste HTML-encoded &

Prompt discipline:
- Always enforce INGREDIENTS_LIST strictness in LLM prompt
- Return structured JSON with success/error when interacting with services

OCI GenAI minimal snippet (Python):
```python
from oci.generative_ai_inference import GenerativeAiInferenceClient
from oci.generative_ai_inference.models import (
    ChatDetails, OnDemandServingMode, GenericChatRequest, Message, TextContent
)
from oci.auth.signers import InstancePrincipalsSecurityTokenSigner, get_resource_principals_signer

# Use instance/resource principals (no config file)
signer = InstancePrincipalsSecurityTokenSigner()  # or get_resource_principals_signer() in containers

client = GenerativeAiInferenceClient(
    config={},
    signer=signer,
    service_endpoint="$OCI_SERVICE_ENDPOINT"
)
chat_details = ChatDetails(
    compartment_id="$OCI_COMPARTMENT_OCID",
    serving_mode=OnDemandServingMode(model_id="$LLM_MODEL_ID"),
    chat_request=GenericChatRequest(
        messages=[Message(role="USER", content=[TextContent(text=PROMPT)])],
        temperature=$LLM_TEMPERATURE,
        top_p=$LLM_TOP_P,
        max_tokens=$LLM_MAX_TOKENS,
    ),
)
resp = client.chat(chat_details=chat_details)
text = resp.data.chat_response.choices[0].message.content[0].text
```

Learnings from Phase 1:
- Use OCI GenAI chat API for interactive models like Grok-4:
  - GenericChatRequest with Message(TextContent)
  - ChatDetails with OnDemandServingMode(model_id)
  - Response parsing: response.data.chat_response.choices[0].message.content[0].text
- DO NOT use ChatDetails(messages=..., inference_params=...) — these fields are not accepted on ChatDetails

Learnings from Phase 2:
- GET and POST $API_BASE_PATH/recipe implemented returning { model, cuisine, dietary, recipe }
- Health endpoints exposed at /health and /ready with readiness checks
- Structured logging verified in stdout; helpful for debugging and observability

Import discipline (Python):
- Inside recipe-api/app/* use package‑relative imports to avoid ModuleNotFoundError under uvicorn module paths.
  Example:
    from .core.config import get_settings
    from .services.genai_service import chat
- Avoid absolute imports like:
    from app.core.config import get_settings
  unless the package is installed or PYTHONPATH is adjusted to include the repository root.

Runtime and setup learnings (2025-12-03):
- Runtime floor: Python 3.10+ (prefer 3.11/3.12).
- Venv discipline: always recreate `.venv` after changing the system interpreter.
- Upgrade tooling before installs: upgrade `pip` prior to `pip install -r ...`.
- Break long operations into steps to avoid terminal timeouts.
- Oracle Linux specifics: use `alternatives` or module streams to get Python 3.12+, or use `pyenv`.

Setup verification checklist:
```bash
./.venv/bin/python --version
pgrep -fa uvicorn || true
ss -ltnp | grep ":$API_PORT" || true
curl -s "http://localhost:$API_PORT$API_BASE_PATH/recipe" | head -c 200 || true
```

EOF
  echo "Wrote: ${DEST}/memory-bank/systemPatterns.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/systemPatterns.md (use -f to overwrite)"
fi

# memory-bank/techContext.md
if [[ ! -f "${DEST}/memory-bank/techContext.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/techContext.md" << 'EOF'
# techContext.md

Technologies:
- Python 3.10+
- FastAPI, Uvicorn
- Streamlit
- OCI Python SDK (oci) for Generative AI and auth
- YAML config management
- Requests (Streamlit client)

Development setup:
- Local (venv-first):
  - python3 -m venv .venv
  - source .venv/bin/activate
  - pip install -r recipe-api/requirements.txt
  - From repo root: python3 -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT --reload
  - Or: cd recipe-api && python3 -m uvicorn app.main:app --host 0.0.0.0 --port $API_PORT --reload
  - Docs: http://localhost:$API_PORT/docs
  - API endpoint: http://localhost:$API_PORT$API_BASE_PATH/recipe
- Containers:
  - Docker build + push to OCIR
- OCI:
  - Container Instances (API & Streamlit)
  - API Gateway (routes /api/* to API)
  - Load Balancer (public frontend to Streamlit)

Curl tips:
- Use the configured base path (default $API_BASE_PATH).
  - GET:  curl -s "http://localhost:$API_PORT$API_BASE_PATH/recipe?cuisine=Mexican&dietary=vegan" | jq
  - POST: curl -s -X POST "http://localhost:$API_PORT$API_BASE_PATH/recipe" -H "Content-Type: application/json" -d '{"cuisine":"Mexican","dietary":"vegan"}' | jq
- Ensure & is used in the shell (not HTML-encoded &).

Configuration (workshop-config.yaml):
- oci.service_endpoint (region-specific GenAI endpoint)
- oci.auth_mode (default "instance_principals")
- oci.compartment_ocid (deployment + GenAI)
- Compartment resolution precedence: config.oci.compartment_ocid -> COMPARTMENT_ID env -> signer.get_claim("res_tenant")
- llm.model_id / temperature / top_p / max_tokens
- api paths and ports, streamlit port
- docker registry/namespace/repo/tags
- container_instance shapes, subnets, private IPs
- api_gateway route_prefix, load_balancer subnets/health check

Security & secrets:
- Never hardcode secrets in code or YAML
- Use env vars or platform secrets for API keys, tenancy auth
- COMPARTMENT_ID env injected into API containers

Dependencies:
- fastapi, uvicorn, oci, pyyaml, requests, streamlit

OCI readiness for local dev:
- Instance or Resource Principals signer must be available; readiness checks verify signer availability, service endpoint, and model id

Learnings from Phase 1:
- OCI SDK 2.163.0+ supports GenerativeAiInferenceClient.chat
- Import models: from oci.generative_ai_inference.models import ChatDetails, OnDemandServingMode, GenericChatRequest, Message, TextContent
- Shape:
  - ChatDetails(compartment_id=..., serving_mode=OnDemandServingMode(model_id=...), chat_request=GenericChatRequest(...))
  - Set messages/temperature/top_p/max_tokens on GenericChatRequest
  - DO NOT pass messages or inference_params directly to ChatDetails
- Auth: Prefer InstancePrincipalsSecurityTokenSigner (OCI Compute) or get_resource_principals_signer (containers)
- File structure: recipe-api/app/main.py, app/services/genai_service.py, app/core/config.py
- Run command: python3 -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT --reload (from cwd)

Import discipline:
- Use package‑relative imports inside the app package to avoid ModuleNotFoundError:
    from .core.config import get_settings
    from .services.genai_service import chat
- Do not use absolute from app.core... unless the package is installed or PYTHONPATH is set appropriately.

Runtime and setup learnings (2025-12-03):
- Python runtime floor: Python 3.10+ (prefer 3.11/3.12). Verify:
  ```bash
  python3 --version
  ```
- Recreate venv after interpreter change:
  ```bash
  rm -rf .venv && python3 -m venv .venv
  ```
- Upgrade pip before installs:
  ```bash
  ./.venv/bin/python -m pip install --upgrade pip
  ```
- Install and run in separate steps (avoid long chained commands that can time out):
  ```bash
  ./.venv/bin/pip install -r recipe-api/requirements.txt
  ./.venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT --reload
  ```
- Oracle Linux tip: if system python is old, prefer one of:
  - `sudo alternatives --set python3 /usr/bin/python3.12`
  - `sudo dnf module enable nodejs:20 -y && sudo dnf module enable python39:3.12 -y && sudo dnf module install python3.12 -y` (adjust for distro)
  - `pyenv` to provision a modern interpreter for the project
- Verification checklist:
  ```bash
  ./.venv/bin/python --version
  pgrep -fa uvicorn || true
  ss -ltnp | grep ":$API_PORT" || true
  curl -s "http://localhost:$API_PORT$API_BASE_PATH/recipe" | head -c 200 || true
  ```

EOF
  echo "Wrote: ${DEST}/memory-bank/techContext.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/techContext.md (use -f to overwrite)"
fi

# memory-bank/activeContext.md
if [[ ! -f "${DEST}/memory-bank/activeContext.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/activeContext.md" << 'EOF'
# activeContext.md

Current focus:
- Phased workshop build (curl-first)
  1) GET $API_BASE_PATH/recipe minimal (completed)
  2) Add POST, /health, /ready
  3) Enforce + parse INGREDIENTS_LIST
  4) Add Woolworths search + LLM
EOF
  echo "Wrote: ${DEST}/memory-bank/activeContext.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/activeContext.md (use -f to overwrite)"
fi

# memory-bank/streamlitStandards.md (UI/state/API contract)
if [[ ! -f "${DEST}/memory-bank/streamlitStandards.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/streamlitStandards.md" << 'EOF'
# Streamlit App Standard — UI, State, and API Client Contract (Non‑Negotiable)

Purpose:
- Ensure a consistent, working Streamlit UI that pairs with the FastAPI backend and Woolworths integration.
- Minimize drift when building from scratch by standardizing session state, API calls, UI layout, and reasoning display.

Hard requirements

1) Page config and Title
- st.set_page_config(page_title="What's for Dinner?", page_icon="🍽️", layout="wide")
- st.title("What's for Dinner?")

2) Session state initialization (init_state)
Initialize the following keys exactly once at startup:
- api_base_url: Prefer env API_BASE_URL if set, else default "http://localhost:$API_PORT$API_BASE_PATH" (strip trailing /)
- last_result: None
- cart: [] (list of items where each item is a dict: {name, price?, image?, source})
- sel_cuisine: "" and sel_cuisine_other: ""
- sel_dietary: "" and sel_dietary_other: ""

Provide helpers:
- def base_url() -> str: return st.session_state.api_base_url.rstrip("/")
- def set_api_base_url(url: str) -> None: normalize and store trimmed URL

3) Text helpers
- normalize_reasoning(txt: Optional[str]) -> str:
  - Remove zero-width chars and BOM; convert NBSP to space:
    - \u200b, \u200c, \u200d, \ufeff -> removed; \u00a0 -> space
  - Collapse whitespace to single spaces
  - Collapse space-separated digits into numbers (e.g., "1 2 . 4 7" -> "12.47")
  - Unspl it single-letter runs into tokens (e.g., "p e r k g" -> "perkg")
  - Fix unit tokens: perkg -> "per kg"; perm[lL] -> "per mL"; pergram -> "per gram"; perliter -> "per liter"; perhead -> "per head"
  - Normalize punctuation spacing (no preceding space before punctuation; single space after punctuation)
- extract_title_body(recipe_text: str) -> tuple[str, str]:
  - Title is first line with Markdown header markers stripped (leading # and spaces)
  - Body is remainder joined with newlines
  - Defaults to ("Recipe", "") if empty

4) API client (requests, timeout via STREAMLIT_API_TIMEOUT env)
- call_recipe_post(api: str, cuisine?: str, dietary?: str) -> Optional[Dict[str, Any]]:
  - POST f"{api}/recipe" with JSON payload containing only provided keys
  - Timeout = int(os.getenv("STREAMLIT_API_TIMEOUT", "310"))
  - Return resp.json() on HTTP OK; else st.error with status
- call_recipe_get(api: str, cuisine?: str, dietary?: str) -> Optional[Dict[str, Any]]:
  - GET f"{api}/recipe" with params for provided keys
  - Same timeout; same error handling

5) Sidebar layout and controls
- st.sidebar header "Settings"
- If env API_BASE_URL exists:
  - st.success("Using API_BASE_URL env") and st.caption(current api_base_url)
- Else:
  - st.text_input("API Base URL", default st.session_state.api_base_url, help "Example: http://localhost:$API_PORT$API_BASE_PATH")
  - If changed, call set_api_base_url
- Preferences:
  - Cuisine selectbox with options: ["", "Italian", "Mexican", "Indian", "Chinese", "Thai", "Greek", "Other..."]
  - If "Other..." selected, show text_input "Custom cuisine" and use that value
  - Dietary selectbox with options: ["", "vegetarian", "vegan", "gluten-free", "keto", "pescatarian", "Other..."]
  - If "Other..." selected, show text_input "Custom dietary" and use that value
- Actions:
  - Buttons in two columns: "Generate" (primary) and "Surprise me"

6) Actions behavior
- On Generate: result = call_recipe_post(base_url(), cuisine_value, dietary_value)
- On Surprise me: result = call_recipe_get(base_url(), None, None)
- If a result is returned, store it in st.session_state.last_result

7) Main content layout
- Two columns: left (2), right (1)

Left column:
- Subheader "Recipe"
- If no last_result: st.info("Use the sidebar to set the API URL and press Generate or Surprise.")
- Else:
  - Metadata caption: include any of {model, cuisine, dietary}
  - Recipe display:
    - Extract (title, body) via extract_title_body(last["recipe"] or "")
    - st.markdown(f"### {title}"); st.markdown(body)
  - Divider, then "Ingredients":
    - last["ingredients"] if present; else caption "No parsed ingredients found."
    - Render chips as st.button
EOF
  echo "Wrote: ${DEST}/memory-bank/streamlitStandards.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/streamlitStandards.md (use -f to overwrite)"
fi

# memory-bank/containerStandards.md
if [[ ! -f "${DEST}/memory-bank/containerStandards.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/containerStandards.md" << 'EOF'
# Containerization and OCI Deployment Standard — Docker, OCIR, and Resource Principals (Non‑Negotiable)

Goals:
- Deterministic, small, non-root Python images for API and Streamlit
- OCIR tagging/pushing discipline from workshop-config.yaml
- OCI Container Instances deployment with healthchecks and env injection
- Resource Principals (RP) authentication guidance in containers

Image build (Python):
- Multi-stage (builder wheels -> slim runtime), WORKDIR /app
- pip install --no-cache-dir; copy only runtime artifacts
- Non-root: create uid 10001, USER appuser
- Healthcheck: API -> GET /health; Streamlit -> HEAD /
- EXPOSE $API_PORT (API), $STREAMLIT_PORT (UI) for clarity

Runtime commands:
- API: uvicorn app.main:app --host 0.0.0.0 --port ${API_PORT:-$API_PORT} --workers ${UVICORN_WORKERS:-2}
- UI: streamlit run app.py --server.port=${STREAMLIT_PORT:-$STREAMLIT_PORT} --server.headless=true

. dockerignore (baseline):
- .venv, __pycache__/, *.pyc, .git, .DS_Store, node_modules/, .env, .pytest_cache, .mypy_cache, dist/, build/, .vscode/, .idea/

OCIR:
- docker login -u "<tenancy-namespace>/<username>" <region>.ocir.io (Auth Token)
- docker tag/push using docker.registry from workshop-config.yaml

OCI Container Instances:
- Private IP reuse rule: delete-before-recreate if reusing IP
- Env (API): OCI_SERVICE_ENDPOINT, LLM_MODEL_ID, COMPARTMENT_ID, API_PORT, UVICORN_WORKERS (+ WOOL_* as needed)
- Env (UI): API_BASE_URL, STREAMLIT_PORT
- Ports: $API_PORT (API), $STREAMLIT_PORT (UI)

Resource Principals (containers):
- Default authentication for the GenAI client is Instance/Resource Principals (no config file). Use get_resource_principals_signer() in containers and InstancePrincipalsSecurityTokenSigner() on OCI Compute; keep request shape/response parsing identical.
- Compartment resolution precedence:
  1) settings.oci.compartment_ocid
  2) COMPARTMENT_ID env
  3) signer.get_claim("res_tenant")

Security/observability:
- No secrets baked into images; use env/OCI Secrets
- JSON logs to stdout/stderr; no persistent container FS logs
EOF
  echo "Wrote: ${DEST}/memory-bank/containerStandards.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/containerStandards.md (use -f to overwrite)"
fi

# memory-bank/genaiStandards.md
if [[ ! -f "${DEST}/memory-bank/genaiStandards.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/genaiStandards.md" << 'EOF'
# GenAI Service Standard (OCI Python SDK) — Non‑Negotiable Implementation Contract

Purpose:
- Eliminate misconfiguration when building from scratch by codifying the exact OCI Generative AI client pattern and response parsing required by this workshop.
- Cline must implement GenAI exactly as specified here when prompted to scaffold or fix the backend.

Hard requirements:
1) Client construction
   - Use oci.generative_ai_inference.GenerativeAiInferenceClient
   - Initialize with:
     - signer = InstancePrincipalsSecurityTokenSigner() (or get_resource_principals_signer() in containers)
     - service_endpoint = settings.oci.service_endpoint (from configuration)

2) Chat request shape — exact syntax
   - Build a GenericChatRequest with:
     - messages = [Message(role="USER", content=[TextContent(text=prompt)])]
     - temperature/top_p/max_tokens read from settings.llm.*
   - Build ChatDetails ONLY with:
     - compartment_id = settings.oci.compartment_ocid
     - serving_mode = OnDemandServingMode(model_id=settings.llm.model_id)
     - chat_request = the GenericChatRequest created above
   - DO NOT set messages or inference_params directly on ChatDetails.

3) Response parsing — exact path
   - Always parse the model output from:
     response.data.chat_response.choices[0].message.content[0].text

4) Prompt discipline (Phase 3+)
   - When generating a recipe, the final line MUST be:
     INGREDIENTS_LIST: a, b, c
   - Do not append any characters after that line.
   - Parse that line deterministically downstream.

5) Configuration source of truth
   - All values come from centralized Settings (read from workshop-config.yaml):
     - settings.oci.service_endpoint
     - settings.oci.auth_mode
     - settings.oci.compartment_ocid
     - settings.llm.model_id / temperature / top_p / max_tokens

6) Authentication note
   - Default authentication is Instance or Resource Principals (no config file).
   - For containers, use get_resource_principals_signer(); for OCI Compute, use InstancePrincipalsSecurityTokenSigner(); keep ChatDetails/GenericChatRequest contract identical.

Canonical implementation (reference):
```python
from oci.generative_ai_inference import GenerativeAiInferenceClient
from oci.generative_ai_inference.models import (
    ChatDetails,
    OnDemandServingMode,
    GenericChatRequest,
    Message,
    TextContent,
)
from oci.auth.signers import InstancePrincipalsSecurityTokenSigner, get_resource_principals_signer

# Prefer instance/resource principals (no config file)
signer = InstancePrincipalsSecurityTokenSigner()  # or get_resource_principals_signer() in containers

client = GenerativeAiInferenceClient(
    config={},
    signer=signer,
    service_endpoint=settings.oci.service_endpoint,
)
```
EOF
  echo "Wrote: ${DEST}/memory-bank/genaiStandards.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/genaiStandards.md (use -f to overwrite)"
fi

# memory-bank/woolworthsStandards.md (no API key required)
if [[ ! -f "${DEST}/memory-bank/woolworthsStandards.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/woolworthsStandards.md" << 'EOF'
# Woolworths Integration Standard — Async Search + LLM-backed Selection (Non‑Negotiable Contract)

Purpose:
- Provide a deterministic, performant pattern for Woolworths product search and LLM-based selection.

Core contract:
1) HTTP client and base URL
   - Use httpx.AsyncClient with:
     - base_url = "https://www.woolworths.com.au/apis"
     - timeout = httpx.Timeout(connect=3.0, read=WOOL_TIMEOUT, write=WOOL_TIMEOUT, pool=WOOL_TIMEOUT)
       where WOOL_TIMEOUT defaults to 6.0 (seconds) when env unset
   - Provide an aclose() method to close the client.

2) Required headers (browser-like)
   - Send minimal browser UA and common headers to match UI endpoints.
   - API key header NOT required for UI endpoints.

3) Endpoint and parameters
   - Primary search endpoint: GET /ui/Search/products
   - Required query param: searchTerm (cleaned ingredient name)
   - Optional query param: storeId (if present in env WOOLWORTHS_STORE_ID)

4) Concurrency/backpressure
   - asyncio.Semaphore limits: WOOL_CONCURRENCY (default 5), WOOL_REASON_CONCURRENCY (default 1)

5) Retries/logging
   - Lightweight retry/backoff; log basic debug without secrets

6) Search cleaning and AU synonyms
   - Implement cleaner and AU term mapping (capsicum, coriander, spring onion, rocket, beef mince, plain flour, icing sugar, bicarb soda, cornflour, wholemeal, …)

7) Result flattening and shape
   - Extractor MUST flatten nested Products wrappers into a flat list of product dicts (handles {"Products":[{"Products":[...]} , ...]})
   - Map fields robustly:
     - displayName: DisplayName | displayName | Name | Description
     - image: SmallImageFile | smallImageFile | SmallImageUrl | MediumImageFile | LargeImageFile | ImageUrl | imageUrl | Thumbnail | ThumbnailURL | Image, or first from Images/DetailsImagePaths
     - price: Price | price | InstorePrice | UnitPrice | UnitPriceValue | RetailPrice | CupPrice, or nested in Prices/Pricing/PriceInfo objects/lists; parse "$12.00" strings to floats
   - De‑duplicate by displayName

8) Caching
   - In-memory cache clean_term -> (timestamp, items); TTL WOOL_CACHE_TTL (default 300s); return top-K WOOL_TOPK (default 2)

9) Selection and reasoning
   - Output exactly ONE selected product per ingredient (best match). Use LLM reasoning (via GenAIService.chat) over top‑K candidates but return only the single best candidate in the API response.
   - On timeout/error, fallback to a heuristic message and continue

10) Per-ingredient top-N reasoning
    - WOOL_REASON_TOPN (default 2) to limit reasoning

11) Timeouts
    - WOOL_PER_ING_TIMEOUT / WOOL_REASON_TIMEOUT (default 300.0s)

12) Public async API
    - async def search_products(term: str) -> List[Dict[str, Any]]
    - async def select_for_ingredients(ingredients: List[str], reason_topn: Optional[int] = None) -> List[Dict[str, Any]]

Environment variables (defaults):
- WOOL_TOPK=2                  # candidate pool size per ingredient (LLM considers up to this many)
- WOOL_CONCURRENCY=5
- WOOL_TIMEOUT=6.0
- WOOL_PER_ING_TIMEOUT=300.0
- WOOL_REASON_TIMEOUT=300.0
- WOOL_REASON_CONCURRENCY=1
- WOOL_CACHE_TTL=300
- WOOLWORTHS_STORE_ID (optional)
- WOOL_REASON_MANDATORY=1
- WOOL_REASON_TOPN=all
- WOOL_MAX_INGREDIENTS=5       # cap ingredients processed per request (API trims to first N)
EOF
  echo "Wrote: ${DEST}/memory-bank/woolworthsStandards.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/woolworthsStandards.md (use -f to overwrite)"
fi

# memory-bank/systemdStandards.md
if [[ ! -f "${DEST}/memory-bank/systemdStandards.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/systemdStandards.md" << 'EOF'
# Systemd Services Standard — FastAPI (uvicorn) and Streamlit on Oracle Linux

Purpose:
- Define a repeatable, robust pattern to run the FastAPI backend and Streamlit UI as systemd services.
- Ensure both start on boot, restart on failure, use the project WorkingDirectory, and auto-detect a Python venv if present.

Root cause analysis for past failures:
- Quoting/interactive shell issues: Using “sudo bash -lc '...heredoc...'” from interactive shells led to “bash: -lc: command not found” due to quoting and shell heredoc parsing across terminals. Fix: Write unit files with sudo tee and use absolute ExecStart commands inside systemd units.
- ExecStart shell mismatch: Relying on /bin/sh semantics or implicit shells caused environment differences. Fix: Explicitly invoke /usr/bin/bash -lc in ExecStart.
- Python/venv ambiguity: Services sometimes ran with system python instead of venv. Fix: ExecStart detects .venv/bin/python first, else falls back to python3.
- Port conflicts: Dev servers already bound to $API_PORT/$STREAMLIT_PORT prevented services from starting. Fix: Stop dev servers before systemd start; use fuser to free ports if needed.
- Missing daemon-reload/enable: After creating units, forgetting systemctl daemon-reload and enable caused startup-on-boot failures. Fix: Always reload and enable.

Non‑negotiable service contract:
- Two services:
  - recipe-api.service (FastAPI via uvicorn)
  - recipe-streamlit.service (Streamlit UI)
- WorkingDirectory: the project folder (e.g., /home/opc/vibe-test6 or /home/opc/workshop)
- Restart policy: Restart=always, RestartSec=5
- Boot target: WantedBy=multi-user.target
- Venv auto-detect: Use .venv/bin/python if present, else system python3
- Environment: Read optional project .env and /etc/default overrides
- Use /usr/bin/bash -lc in ExecStart to guarantee a predictable shell environment

Canonical unit files (templates):
1) /etc/systemd/system/recipe-api.service
[Unit]
Description=Recipe API (FastAPI / uvicorn)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=opc
WorkingDirectory=/home/opc/vibe-test6
EnvironmentFile=-/home/opc/vibe-test6/.env
EnvironmentFile=-/etc/default/recipe-api
Environment=API_PORT=$API_PORT
Environment=UVICORN_WORKERS=2
ExecStart=/usr/bin/bash -lc 'PY=$([ -x .venv/bin/python ] && echo .venv/bin/python || command -v python3); exec "$PY" -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port "${API_PORT:-$API_PORT}" --workers "${UVICORN_WORKERS:-2}"'
Restart=always
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target

2) /etc/systemd/system/recipe-streamlit.service
[Unit]
Description=Recipe Streamlit UI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=opc
WorkingDirectory=/home/opc/vibe-test6
EnvironmentFile=-/home/opc/vibe-test6/.env
EnvironmentFile=-/etc/default/recipe-streamlit
Environment=STREAMLIT_PORT=$STREAMLIT_PORT
ExecStart=/usr/bin/bash -lc 'PY=$([ -x .venv/bin/python ] && echo .venv/bin/python || command -v python3); exec "$PY" -m streamlit run recipe-streamlit-app/app.py --server.port="${STREAMLIT_PORT:-$STREAMLIT_PORT}" --server.headless=true'
Restart=always
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target

Setup commands (idempotent):
- Create units:
  sudo tee /etc/systemd/system/recipe-api.service >/dev/null <<'EOF'
  ...unit content above...
  EOF

  sudo tee /etc/systemd/system/recipe-streamlit.service >/dev/null <<'EOF'
  ...unit content above...
  EOF

- Reload and enable:
  sudo systemctl daemon-reload
  sudo systemctl enable recipe-api.service recipe-streamlit.service

- Stop dev servers and start services:
  sudo fuser -k $API_PORT/tcp || true
  sudo fuser -k $STREAMLIT_PORT/tcp || true
  sudo systemctl start recipe-api.service
  sudo systemctl start recipe-streamlit.service

Verification:
- Status:
  systemctl status --no-pager recipe-api.service
  systemctl status --no-pager recipe-streamlit.service
- Logs:
  sudo journalctl -u recipe-api.service -f
  sudo journalctl -u recipe-streamlit.service -f
- HTTP checks:
  curl -s http://localhost:$API_PORT/ready | jq .
  curl -s http://localhost:$API_PORT$API_BASE_PATH/recipe | jq '{ingredients_len:(.ingredients|length),products_len:(.products|length)}'
  curl -sI http://localhost:$STREAMLIT_PORT/ | head -n 1

Environment overrides (optional):
- Project .env is read by both services
- /etc/default/recipe-api examples:
  API_PORT=$API_PORT
  UVICORN_WORKERS=2
- /etc/default/recipe-streamlit examples:
  STREAMLIT_PORT=$STREAMLIT_PORT
  API_BASE_URL=http://localhost:$API_PORT$API_BASE_PATH

Operational notes:
- If you change unit files: sudo systemctl daemon-reload && sudo systemctl restart recipe-*.service
- If venv is created after units were made: No changes needed; ExecStart detects .venv/bin/python on next restart.
- Prefer clearing dev listeners before starting services to avoid EADDRINUSE errors.
EOF
  echo "Wrote: ${DEST}/memory-bank/systemdStandards.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/systemdStandards.md (use -f to overwrite)"
fi

# memory-bank/devopsStandards.md
if [[ ! -f "${DEST}/memory-bank/devopsStandards.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/devopsStandards.md" << 'EOF'
# DevOps Standards — OCI DevOps Projects, Repositories, and Git (Non‑Negotiable)

Purpose:
- Provide a deterministic, repeatable pattern to create an OCI DevOps Project/Repo and push code with minimal friction.
- Capture operational gotchas learned from prior automation (CLI flags, SSH/HTTPS auth, merge strategy, temp file hygiene).

Core contract:
1) Notifications topic is mandatory for DevOps projects
   - Create or locate a Notifications topic and pass it via: --notification-config '{"topicId":"<TOPIC_OCID>"}'
   - If name conflict exists, search tenancy subtree to retrieve the existing topic OCID by name.

2) DevOps CLI usage (region ap-sydney-1 examples)
   - Create project:
     oci devops project create --compartment-id <COMP_OCID> --name "<PROJECT_NAME>" \
       --description "DevOps project for workshop" \
       --notification-config '{"topicId":"<TOPIC_OCID>"}'
   - Create repository (hosted):
     oci devops repository create --project-id <PROJECT_OCID> \
       --name "<REPO_NAME>" --repository-type HOSTED --default-branch main
   - List/get URLs:
     oci devops repository get --repository-id <REPO_OCID> --query 'data."ssh-url"' --raw-output
     oci devops repository get --repository-id <REPO_OCID> --query 'data."http-url"' --raw-output

3) SSH first, HTTPS fallback
   - Add host key: ssh-keyscan -H devops.scmservice.<region>.oci.oraclecloud.com >> ~/.ssh/known_hosts
   - Use user SSH config/identity; prefer IdentitiesOnly=yes.
   - If SSH fails (Permission denied (publickey)), user must add their SSH public key in OCI DevOps User Settings.
   - Fallback to HTTPS with OCI Auth Token when needed.

4) Git push flow and divergent branches
   - Initialize repo and add .gitignore for Python/venv/temp/CI outputs.
   - Remove temporary artifacts before first push:
     temp_test/, temp_test2/, tmp-verify/, tmp-workshop/
     ci_*out.json, *.out.json, ci_list*.json, ci_ids.txt, recipe-streamlit-app/streamlit.log
   - If remote contains default content:
     git fetch origin main
     git pull --no-rebase --allow-unrelated-histories origin main
     git push -u origin main
   - Always set upstream on first successful push.

5) Line endings and shell pitfalls
   - Avoid CRLF in shell commands/scripts; CRLF can cause $'\r' errors.
   - Use Unix line endings LF and quote JSON for --notification-config safely.

6) Documentation update
   - The workshop guide (Phase 9 Optional) includes a copy/paste prompt to automate topic/project/repo creation and a clean push.

EOF
  echo "Wrote: ${DEST}/memory-bank/devopsStandards.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/devopsStandards.md (use -f to overwrite)"
fi

# memory-bank/mcpStandards.md
if [[ ! -f "${DEST}/memory-bank/mcpStandards.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/mcpStandards.md" << 'EOF'
# MCP Server Standards — Local Developer Tooling (Non‑Negotiable for this Workshop)

Purpose:
- Provide a deterministic pattern to expose your Recipe API to MCP‑aware tools (e.g., Cline/Claude) without changing the app or Streamlit UI.
- MCP is for dev/LLM tooling only. Streamlit continues to call the REST API directly.

Implementation choices:
- Runtime: Node.js ≥ 20 (Oracle Linux 9: `sudo dnf module enable nodejs:20 -y && sudo dnf module install nodejs:20 -y`)
- SDK: @modelcontextprotocol/sdk ^0.6
- HTTP: axios (timeout ≤ 300s)
- Language: TypeScript; output bin: build/index.js (chmod +x)
- Project path: /home/opc/Documents/Cline/MCP/recipe-api-mcp

Tools (names and contracts):
- get_recipe
  - Method: GET /recipe
  - Arguments (optional): { cuisine?: string, dietary?: string }
  - Returns: JSON from API as text content (no reshaping)
- post_recipe
  - Method: POST /recipe
  - Body (optional): { cuisine?: string, dietary?: string }
  - Returns: JSON from API as text content

Configuration:
- SERVICE_BASE_URL env controls backend base URL and MUST match your API’s mounting:
  - If API routes are at root (e.g., /recipe): SERVICE_BASE_URL="http://<host>:<port>"
  - If API is behind a gateway base path (/api/v1): SERVICE_BASE_URL="https://<gw>/api/v1"
- MCP registration (VS Code / Cline):
  - File: ~/.vscode-server/data/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json
  - Entry key: "recipe-api"
  - Required fields: { "command":"node", "args":[ "/home/opc/Documents/Cline/MCP/recipe-api-mcp/build/index.js" ], "env": { "SERVICE_BASE_URL":"..." }, "disabled": false, "autoApprove": [] }

Resilience and timeouts:
- axios: timeout 300000 ms (300s) to match LLM latencies
- Always trim optional string args; don’t send empty fields
- Return clean error text: include upstream JSON error body if provided

Build/test checklist:
1) npm install --no-audit --no-fund
2) npm run build (tsc && chmod +x build/index.js)
3) Register/update cline_mcp_settings.json with SERVICE_BASE_URL aligned to your API
4) Test tools:
   - post_recipe { "cuisine": "Indian", "dietary": "vegetarian" }
   - get_recipe with no args (surprise)

Operational guidance:
- Do not run MCP inside the Streamlit container; MCP is not a browser API.
- For the Streamlit UI, set API_BASE_URL to your API Gateway URL; do not bridge MCP to HTTP for the UI.

Common pitfalls:
- 404 Not Found via MCP: SERVICE_BASE_URL included /api/v1 but backend is mounted at root (/recipe), or vice‑versa.
- Short timeouts: increase to 300s to accommodate GenAI + product selection.

EOF
  echo "Wrote: ${DEST}/memory-bank/mcpStandards.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/mcpStandards.md (use -f to overwrite)"
fi

echo "Memory bank setup complete."

# -----------------------------------------------------------------------------
# Mirror memory bank into .clinerules and aggregate AGENTS.md
# -----------------------------------------------------------------------------
mkdir -p "${DEST}/.clinerules"

pairs=(
  "activeContext.md:00-active-context.md"
  "projectbrief.md:01-project-brief.md"
  "systemPatterns.md:02-system-patterns.md"
  "techContext.md:03-tech-context.md"
  "productContext.md:04-product-context.md"
  "genaiStandards.md:05-genai-service-standard.md"
  "woolworthsStandards.md:06-woolworths-service-standard.md"
  "streamlitStandards.md:07-streamlit-app-standard.md"
  "containerStandards.md:08-container-standards.md"
  "systemdStandards.md:09-systemd-services.md"
  "devopsStandards.md:10-devops-standards.md"
  "mcpStandards.md:11-mcp-standards.md"
)

for pair in "${pairs[@]}"; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  if [[ -f "${DEST}/memory-bank/${src}" ]]; then
    if [[ -f "${DEST}/.clinerules/${dst}" && "${FORCE}" -ne 1 ]]; then
      echo "Exists (skipping): ${DEST}/.clinerules/${dst} (use -f to overwrite)"
    else
      cp -f "${DEST}/memory-bank/${src}" "${DEST}/.clinerules/${dst}"
      echo "Mirrored: memory-bank/${src} -> .clinerules/${dst}"
    fi
  else
    echo "Warning: missing source file ${DEST}/memory-bank/${src} (skipped)"
  fi
done

# Aggregate AGENTS.md
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
      "11-mcp-standards.md"
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

# -----------------------------------------------------------------------------
# workshop-config.yaml (now with auth_mode and no config_path)
# -----------------------------------------------------------------------------
if [[ ! -f "${DEST}/workshop-config.yaml" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/workshop-config.yaml" << 'EOF'
# workshop-config.yaml - Edit with your OCI and project details

oci:
  service_endpoint: "https://inference.generativeai.us-chicago-1.oci.oraclecloud.com"  # Adjust for your region (e.g., au-sydney-1)
  auth_mode: "instance_principals"  # Use Instance/Resource Principals signer; no config file needed
  compartment_ocid: "ocid1.compartment.oc1..aaaaaaaaf5srevccb2moc76cxaanrkel6m7dxe3z4o5yvpeql2jmxqzsqkaq"

llm:
  model_id: "xai.grok-4-fast-reasoning"  # Or other supported model
  temperature: 0.7
  top_p: 0.9
  max_tokens: 2000

api:
  base_path: "/api/v1"
  port: 8010

streamlit:
  port: 8501

docker:
  registry: "syd.ocir.io/sdncspltazsk/recipe-api"
  tag: "latest"

deployment:
  container_instance_shape: "CI.Standard.A1.Flex"
  subnet_ocid: "ocid1.subnet.oc1.ap-sydney-1.aaaaaaaaovukl5n4ty62riay3z4h2y6diuekqq5saw4f6575m3nrngbn2tdq"
  private_ip: "172.16.40.10"
  # For API Gateway and Load Balancer: set route_prefix, health_check_path, etc.

api_gateway:
  display_name: "vibe-api-public-gw"
  type: "PUBLIC"                   # PUBLIC (default) or PRIVATE
  subnet_id: "ocid1.subnet.oc1.ap-sydney-1.aaaaaaaawtsy7pz5wvi75rk22asb3v444iju3boczutiqijzhtlpbw6hwngq"

streamlit_lb:
  display_name: "vibe-workshop-streamlit-lb"
  shape: "flexible"
  is_public: true
  subnet_ids:
    - "ocid1.subnet.oc1.ap-sydney-1.aaaaaaaawtsy7pz5wvi75rk22asb3v444iju3boczutiqijzhtlpbw6hwngq"
  listener_port: 80
  backend_host: "localhost"        # Set to your VM's private IP if needed
  backend_port: 8501
  health_check_path: "/"
  health_check_protocol: "HTTP"
  health_check_port: 8501
EOF
  echo "Wrote: ${DEST}/workshop-config.yaml"
else
  echo "Exists (skipping): ${DEST}/workshop-config.yaml (use -f to overwrite)"
fi

# -----------------------------------------------------------------------------
# recipe-guide.json (prompt-only guide; no code or tech details)
# -----------------------------------------------------------------------------
if [[ ! -f "${DEST}/recipe-guide.json" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/recipe-guide.json" << 'EOF'
{
  "title": "Recipe Workshop - Prompt Guide",
  "overview": "Build the application step-by-step using natural language prompts. Keep technical details hidden in memory-bank/*.md and workshop-config.yaml. Cline enforces non‑negotiable standards from .clinerules/*.md and uses memory-bank docs for context. This guide uses outcome-focused prompts only.",
  "phases": [
    {
      "id": "p1",
      "title": "Minimal API: GET endpoint",
      "prompt": "Create a minimal backend API that exposes GET /api/v1/recipe which returns a randomly generated dinner recipe as JSON {recipe: string}. Make it run locally on port 8010 and provide a curl example to test."
    },
    {
      "id": "p2",
      "title": "Inputs and health",
      "prompt": "Add POST /api/v1/recipe to accept optional cuisine and dietary preferences. Add /health and /ready endpoints for basic service checks. Read the base path from configuration (default /api/v1). Return structured JSON { model, cuisine, dietary, recipe }. Readiness should verify signer availability and that service endpoint and model id are set."
    },
    {
      "id": "p3",
      "title": "Enforce and parse ingredients",
      "prompt": "Ensure every recipe text ends with a single line: 'INGREDIENTS_LIST: a, b, c'. Parse that line into a structured array named 'ingredients' and include it in the API response."
    },
    {
      "id": "p4",
      "title": "Add Woolworths products with LLM reasoning",
      "prompt": "For each ingredient, search a supermarket catalog and suggest products with a simple total price. Follow the Woolworths Integration Standard (primary endpoint: GET /ui/Search/products with browser-like headers; return top-2 candidates; prefer SmallImageFile for images; include brief 'reasoning' with heuristic fallback on timeout). Include a products array like [{ displayName, price, image, reasoning }]. Handle rate limits and errors gracefully."
    },
    {
      "id": "p5",
      "title": "Simple UI",
      "prompt": "Create a simple Streamlit UI (per Streamlit App Standard) that calls the API, shows the recipe, clickable ingredient chips, and a running total price. Persist state with st.session_state, allow API_BASE_URL override via env, normalize reasoning text, and include a Debug expander showing the raw API payload."
    },
    {
      "id": "p6",
      "title": "Package and deployment",
      "prompt": "Containerize the API using the approved Dockerfile pattern aligned with devops-recipe: python:3.11-slim base, non-root user (uid 1000), EXPOSE 8000, HEALTHCHECK curl -f http://localhost:8000/health, and run uvicorn on port 8000 with 2 workers. Push the image to OCIR, then deploy to OCI Container Instances (CI.Standard.E4.Flex) with a private IP; delete any existing instance first when reusing the same private IP. After deploy, update API Gateway backends to http://<PRIVATE_IP>:8000 and verify /health. Keep the GenAI request/response shape exactly per standards; Resource Principals auth is the default in containers."
    }
  ],
  "notes": "Keep source-of-truth technical guidance in memory-bank/*.md and workshop-config.yaml. .clinerules/*.md contains the active, non‑negotiable standards Cline must enforce."
}
EOF
  echo "Wrote: ${DEST}/recipe-guide.json"
else
  echo "Exists (skipping): ${DEST}/recipe-guide.json (use -f to overwrite)"
fi

# -----------------------------------------------------------------------------
# Defaults and helpers
# -----------------------------------------------------------------------------
if [[ ! -f "${DEST}/.env" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/.env" << 'EOF'
WOOL_REASON_MANDATORY=1
WOOL_REASON_TOPN=all
EOF
  echo "Wrote: ${DEST}/.env (LLM-first defaults)"
else
  echo "Exists (skipping): ${DEST}/.env (use -f to overwrite)"
fi


echo "Workshop pack setup complete."

: "${VERBOSE:=}"
# Console tips suppressed by default. Set VERBOSE=1 to print guidance after setup.
if [[ -z "${VERBOSE:-}" ]]; then
  exit 0
fi

if [[ -n "${VERBOSE:-}" ]]; then
echo ""
echo "---------------------------------------------"
echo "IMPORTANT: LLM Reasoning Normalization and UI Standard (Learning 2025-11-26)"
echo "---------------------------------------------"
echo "When integrating LLM-backed product reasoning in recipe apps:"
echo "  - All LLM reasoning must be cleaned/normalized to human-readable form before display."
echo "  - Any UI (esp. Streamlit) MUST show 'LLM reasoning' expander/section ONLY if the explanation after the label is nonempty/meaningful."
echo "  - Do not display empty or label-only 'LLM reasoning' headings. Always strip/skip LLM label prefixes and collapse split or artefactual output."
echo "  - This correction must be reflected both in .clinerules and memory-bank to enforce consistent UX/lab quality and prevent confusion."
echo ""
echo "See recipe-streamlit-app/app.py and normalization helpers for the latest implementation."
echo "---------------------------------------------"
echo "IMPORTANT: Woolworths/GenAI Product Reasoning Output Standard (Learning 2025-11-26)"
echo "---------------------------------------------"
echo "When integrating Woolworths supermarket product search in AI-powered recipes:"
echo "  - Your API must use LLM selection reasoning by default for all main-ingredient product selections."
echo "  - Always use an async selector like 'select_for_ingredients' that calls GenAI to choose and reason about the best product per ingredient."
echo "  - Each item in products[] must include a 'reasoning' field, generated from GenAI, explaining the product choice (or a clear heuristic fallback message if LLM fails)."
echo "  - Do NOT release solutions that only return raw search results – reasoning visibility is mandatory for repeatable, debuggable, and value-aligned workshops."
echo ""
echo "See recipe-api/app/services/woolworths_service.py and recipe-api/app/main.py for the required workflow."
echo "---------------------------------------------"
echo "IMPORTANT: FastAPI Versioned Routing Standard (New Learning, 2025-11-26)"
echo "---------------------------------------------"
echo "Workshops must register API handlers under the correct path prefix using APIRouter, e.g.:"
echo "  api_v1 = APIRouter(prefix=\"$API_BASE_PATH\")"
echo "  @api_v1.get(\"/recipe\")"
echo "  ... app.include_router(api_v1) ..."
echo "If you only register your route as /recipe, the path $API_BASE_PATH/recipe will return 404, even if your handler logic is sound. Always check the memory bank for the required API contract, and mount FastAPI routers accordingly. This rule prevents the common 'route not found' lab issues. Do NOT repeat this in memory bank or clinerules—it's solely noted here for initial scaffolding and lab setup."
echo "---------------------------------------------"
echo "Next: Use recipe-guide.json prompts. After building the API, run:"
echo "  python3 -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT --reload"
echo "API endpoint (default): http://localhost:$API_PORT$API_BASE_PATH/recipe"
echo ""
echo "Performance tuning (Woolworths):"
echo "  export WOOL_TOPK=2              # compare only top-2 products per ingredient"
echo "  export WOOL_CONCURRENCY=3       # parallel product lookups (semaphore)"
echo "  export WOOL_TIMEOUT=300.0       # per-request timeout seconds"
echo "  export WOOL_PER_ING_TIMEOUT=300.0 # per-ingredient selection timeout"
echo "  export WOOL_REASON_TIMEOUT=300.0  # max seconds to allow LLM product_reasoning per ingredient"
echo "  export WOOL_REASON_CONCURRENCY=1  # limit concurrent LLM reasoning calls to reduce timeouts/throttling"
echo "  export WOOL_CACHE_TTL=600         # cache Woolworths search results (seconds)"
echo "  export STREAMLIT_API_TIMEOUT=300  # Streamlit client request timeout (seconds)"
echo "  export WOOL_REASON_MANDATORY=1  # enforce LLM reasoning for all ingredients by default"
echo "  export WOOL_REASON_TOPN=all     # explicit all-ingredients reasoning (ignored if MANDATORY=1)"
echo "  # optional store scoping for relevance:"
echo "  export WOOLWORTHS_STORE_ID=3024"
echo ""
echo "Frontend (Streamlit) tips:"
echo "  python -m streamlit run recipe-streamlit-app/app.py --server.port=$STREAMLIT_PORT --server.headless=true"
echo "  export API_BASE_URL=http://localhost:$API_PORT$API_BASE_PATH  # or your API Gateway URL"
echo "  # Note: This setup script no longer generates a run_streamlit.sh helper; create your own local wrapper if desired."
echo "  # The UI shows product reasoning in an expander when full reasoning is enabled by API settings."
echo "  # A Debug expander displays the raw API payload for verification."
echo ""
echo "After building the API, ensure dependencies (includes httpx) are installed:"
echo "  pip install -r recipe-api/requirements.txt"

echo ""
echo "---------------------------------------------"
echo "IMPORTANT: Systemd Absolute Path & Repeatable Startup Rule (Learning 2025-11-26)"
echo "---------------------------------------------"
echo "To reliably run FastAPI and Streamlit under systemd:"
echo "  1. All unit files MUST use absolute WorkingDirectory and EnvironmentFile values (no shell \$(pwd))."
echo "  2. Always run sudo systemctl daemon-reload, enable, and start after editing/creating unit files, not just copy."
echo "  3. Stop any manual dev servers before starting systemd services to avoid port conflicts ($API_PORT/$STREAMLIT_PORT)."
echo "  4. Always test each service with systemctl status, curl the API /ready endpoint, and curl -I the Streamlit port to confirm HTTP 200."
echo "  5. Incorporate these as shellscript steps for future lab automation—do not rely on memorybank or clinerules to enforce correct systemdology."
echo ""
echo "See setup_workshop_pack.sh and .clinerules for canonical examples."

echo ""
echo "---------------------------------------------"
echo "IMPORTANT: OCI API Gateway Deployment Updates (Learning 2025-11-26)"
echo "---------------------------------------------"
echo "When updating an OCI API Gateway deployment non-interactively, always pass --force to suppress Y/N overwrite prompts."
echo "Remember: Even with correct config, OCI API Gateway traffic may be blocked by VCN/subnet/Security List/Network Security Group rules, or service NAT restrictions—test external/path reachability after deployment, not just config."
echo "---------------------------------------------"
fi
# Console tips suppressed by default. Set VERBOSE=1 to print guidance. All guidance lives in memory-bank/.clinerules and workshop-config.yaml.

# -----------------------------------------------------------------------------
# Learnings from Streamlit App Build (2025-12-03)
# -----------------------------------------------------------------------------
# Initial FileNotFoundError: The relative path '../workshop-config.yaml' failed because Streamlit's cwd during execution didn't resolve it correctly. Fixed by using absolute path via os.path.dirname(__file__).
# NameError for Optional: Forgot to import typing.Optional and typing.Tuple, causing undefined name errors. Python requires explicit imports for type hints.
# TypeError on None formatting: Attempted to format None as float in f-strings (e.g., ${None:.2f}), which Python doesn't support. Fixed by checking for None and falling back to 0.0 before formatting.
# Why not work first time? Rushed initial implementation missed edge cases (None values, imports, paths). Iterative fixes via tool uses ensured robustness—always test assumptions like paths and data types.
