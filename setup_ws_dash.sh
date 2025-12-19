#!/usr/bin/env bash
#
# One-shot script to scaffold the Workshop Memory Bank, workshop-config, and ancillary docs only.

# Usage:
#   chmod +x ./setup_ws_dash.sh
#   ./setup_ws_dash.sh                      # write into current directory, skip existing files
#   ./setup_ws_dash.sh -f                   # force overwrite existing files
#   ./setup_ws_dash.sh -d /path/to/project  # write into a different directory
#   ./setup_ws_dash.sh -d /path -f          # write and overwrite there
#   ./setup_ws_dash.sh -O                   # open firewall ports (8010 API, 7860/7861 Gradio, 8050/8051 Dash) and add iptables ACCEPT rules
#   ./setup_ws_dash.sh -G                   # open ONLY Gradio UI ports (7860/7861) and API port 8010
#   ./setup_ws_dash.sh -D                   # open ONLY Dash UI ports (8050/8051) and API port 8010
#   ./setup_ws_dash.sh -T                   # run bounded first-go smoke tests (process/ports, API /ready and sample /recipe, UI GET /)
#   ./setup_ws_dash.sh -S                   # scaffold Dash UI (recipe-dash-app/) — OPT-IN ONLY
#
# Creates (if absent or with -f):
#   ./memory-bank/{projectbrief.md,productContext.md,systemPatterns.md,techContext.md,activeContext.md,genaiStandards.md,woolworthsStandards.md,streamlitStandards.md,containerStandards.md,systemdStandards.md,devopsStandards.md,mcpStandards.md,gradioStandards.md,dashStandards.md}
#   ./.clinerules/{00-active-context.md,01-project-brief.md,02-system-patterns.md,03-tech-context.md,04-product-context.md,05-genai-service-standard.md,06-woolworths-service-standard.md,07-streamlit-app-standard.md,08-container-standards.md,09-systemd-services.md,10-devops-standards.md,11-mcp-standards.md,12-gradio-app-standard.md,13-dash-app-standard.md}
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

# Quiet mode: suppress stdout unless VERBOSE is set (errors still go to stderr)
if [[ -z "${VERBOSE:-}" ]]; then
  exec 1>/dev/null
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

# Ensure PyYAML is installed for parsing (quiet, non-interactive)
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  python3 -m pip install --user -q --disable-pip-version-check --no-input pyyaml >/dev/null 2>&1 || true
fi

DEST="."
FORCE=0
OPEN_PORTS=0
OPEN_GRADIO_PORTS=0
OPEN_DASH_PORTS=0
RUN_TESTS=0
SCAFFOLD_UI=0

while getopts ":d:fOTGDS" opt; do
  case "${opt}" in
    d) DEST="${OPTARG}" ;;
    f) FORCE=1 ;;
    O) OPEN_PORTS=1 ;;
    G) OPEN_GRADIO_PORTS=1 ;;
    D) OPEN_DASH_PORTS=1 ;;
    T) RUN_TESTS=1 ;;
    S) SCAFFOLD_UI=1 ;;
    *) ;;
  esac
done

# Normalize DEST to absolute path
DEST="$(cd "${DEST}" && pwd)"

echo "Scaffolding Workshop Pack into: ${DEST}"
echo "Force overwrite: ${FORCE}"
echo "Open ports: ${OPEN_PORTS}"
echo "Run tests: ${RUN_TESTS}"
echo "---------------------------------------------"

# Load defaults from workshop-config.yaml if it exists (or use hard-coded)
load_defaults() {
  if [ -f "${DEST}/workshop-config.yaml" ]; then
    eval "$(DEST="${DEST}" python3 - <<'EOF'
import os, sys, yaml
dest = os.environ.get("DEST", ".")
path = os.path.join(dest, "workshop-config.yaml")
try:
    with open(path, 'r') as f:
        config = yaml.safe_load(f) or {}
except Exception:
    # Silent on missing/invalid YAML for programmatic use
    raise SystemExit(0)

oci = config.get('oci') or {}
llm = config.get('llm') or {}
api = config.get('api') or {}
web = config.get('web_interface') or {}
gradio = config.get('gradio') or {}
docker = config.get('docker') or {}

print(f"export OCI_SERVICE_ENDPOINT='{oci.get('service_endpoint','')}'")
print(f"export OCI_AUTH_MODE='{oci.get('auth_mode','instance_principals')}'")
print(f"export OCI_COMPARTMENT_OCID='{oci.get('compartment_ocid','')}'")
print(f"export LLM_MODEL_ID='{llm.get('model_id','')}'")
print(f"export LLM_TEMPERATURE={llm.get('temperature',0.7)}")
print(f"export LLM_TOP_P={llm.get('top_p',0.9)}")
print(f"export LLM_MAX_TOKENS={llm.get('max_tokens',2000)}")
print(f"export API_BASE_PATH='{api.get('base_path','/api/v1')}'")
print(f"export API_PORT={api.get('port',8010)}")
print(f"export WEB_PORT={web.get('port',8051)}")
print(f"export GRADIO_PORT={gradio.get('port',7860)}")
print(f"export DOCKER_REGISTRY='{docker.get('registry','')}'")
print(f"export DOCKER_TAG='{docker.get('tag','latest')}'")
EOF
)" 2>/dev/null
  else
    echo "workshop-config.yaml not found in ${DEST}. A template will be created; populate it and re-run. No defaults exported."
    # No hard-coded defaults exported when YAML is missing.
  fi
}

# Call to load defaults before scaffolding
load_defaults

# Safe defaults for set -u in informational output
: "${API_PORT:=8010}"
: "${STREAMLIT_PORT:=8501}"

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

# memory-bank/dashStandards.md (Dash UI standard; mirrors into .clinerules/13-dash-app-standard.md)
if [[ ! -f "${DEST}/memory-bank/dashStandards.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/dashStandards.md" << 'EOF'
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
  echo "Wrote: ${DEST}/memory-bank/dashStandards.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/dashStandards.md (use -f to overwrite)"
fi

echo "Memory bank setup complete."

# memory-bank/lbStandards.md — OCI Load Balancer Standards (Non‑Negotiable)
if [[ ! -f "${DEST}/memory-bank/lbStandards.md" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/memory-bank/lbStandards.md" << 'EOF'
# OCI Load Balancer Standards — CLI, Config, Wiring, and Diagnostics (Non‑Negotiable)

Purpose
- Provide a deterministic, repeatable pattern to create and wire an OCI Load Balancer (LB) for the Dash/Recipe workshop.
- Hide operational differences (public vs private, region, subnets, ADs) behind workshop-config.yaml and clear CLI recipes.
- Ensure first‑go success by including robust examples, JSON/flag alternatives, and diagnostics.

Configuration (workshop-config.yaml)
- website_lb.display_name        # e.g., "vibe-workshop-website-lb"
- website_lb.shape               # e.g., "flexible"
- website_lb.listener_port       # e.g., 80
- website_lb.is_public           # true for public LB, false for private LB
- website_lb.subnet_ids          # array of subnet OCIDs
  - Public LB: typically 2 subnets in different ADs (HA best practice). Some tenancies may accept 1 subnet for public, but 2 is recommended.
  - Private LB: single subnet is supported (reachable only within the VCN).

Region derivation
- Derive OCI CLI region from the first subnet OCID (oc1.<region>…).
- Pass --region "<derived>" to all LB commands.

JMESPath / jq notes
- For "display-name" keys, prefer jq filtering:
  oci … list --output json | jq -r '.data[]? | select(."display-name"=="my-lb") | .id'

Standard wiring (public HTTP on port 80)
1) Create Load Balancer (public)
```bash
oci lb load-balancer create \
  --region "<region>" \
  --compartment-id "<compartment-ocid>" \
  --display-name "<display-name>" \
  --shape-name "flexible" \
  --shape-details '{"minimumBandwidthInMbps": 10, "maximumBandwidthInMbps": 100}' \
  --subnet-ids '["<subnet-ocid-1>", "<subnet-ocid-2>"]' \
  --is-private false \
  --wait-for-state SUCCEEDED
```
(Single-subnet public is allowed in some environments; use one value in --subnet-ids.)

2) Backend Set (HTTP health on 8050 for Dash)
```bash
oci lb backend-set create \
  --region "<region>" \
  --load-balancer-id "<lb-ocid>" \
  --name "dash-bs" \
  --policy ROUND_ROBIN \
  --health-checker-protocol HTTP \
  --health-checker-port 8050 \
  --health-checker-url-path "/"
```

3) Add Backend (Dash)
```bash
oci lb backend create \
  --region "<region>" \
  --load-balancer-id "<lb-ocid>" \
  --backend-set-name "dash-bs" \
  --ip-address "172.0.30.236" \
  --port 8050
```

4) Listener (HTTP on port 80 → dash-bs)
```bash
oci lb listener create \
  --region "<region>" \
  --load-balancer-id "<lb-ocid>" \
  --default-backend-set-name "dash-bs" \
  --name "http-listener" \
  --port 80 \
  --protocol HTTP
```

Private LB (single subnet)
```bash
oci lb load-balancer create \
  --region "<region>" \
  --compartment-id "<compartment-ocid>" \
  --display-name "<display-name>-private" \
  --shape-name "flexible" \
  --shape-details '{"minimumBandwidthInMbps": 10, "maximumBandwidthInMbps": 100}' \
  --subnet-id "<subnet-ocid-1>" \
  --is-private true \
  --wait-for-state SUCCEEDED
```
Then wire backend set, backend(s), and listener as above.

Verification
```bash
# Public IP
oci --region "<region>" lb load-balancer get --load-balancer-id "<lb-ocid>" \
  --query 'data."ip-addresses"[0]."ip-address"' --raw-output
# HTTP check
curl -sI http://<IP>/ | head -n 1
```

Diagnostics (work requests)
```bash
oci --region "<region>" lb work-request list-work-requests --compartment-id "<compartment-ocid>" --output json | jq .
oci --region "<region>" lb work-request list-work-request-errors --work-request-id "<WR_ID>" --output json | jq .
oci --region "<region>" lb work-request list-work-request-logs --work-request-id "<WR_ID>" --output json | jq .
```

Common failures and remedies
- Public LB with single subnet: prefer two subnets (different ADs) or use private LB for single subnet.
- “Unknown default backend set”: create backend set first, then listener; verify with:
  oci … backend-set list … | jq -r '.data[]?.name'
- Capacity/shape issues: adjust shape/bandwidth or retry later.
- Quoting issues with "display-name": prefer jq filtering over JMESPath.
EOF
  echo "Wrote: ${DEST}/memory-bank/lbStandards.md"
else
  echo "Exists (skipping): ${DEST}/memory-bank/lbStandards.md (use -f to overwrite)"
fi

# --- First-go helpers (optional) ---
open_ports_gradio() {
  # Open API (8010) and Gradio UI ports (7860/7861) only
  if systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --zone=public --add-port=8010/tcp --permanent || true
    sudo firewall-cmd --zone=public --add-port=7860/tcp --permanent || true
    sudo firewall-cmd --zone=public --add-port=7861/tcp --permanent || true
    sudo firewall-cmd --reload || true
    echo "firewalld ports opened (Gradio/API):"
    sudo firewall-cmd --list-ports | grep -E '8010|7860|7861' || true
  else
    echo "firewalld not active; skipping firewall-cmd (Gradio/API)"
  fi
  for p in 8010 7860 7861; do
    sudo iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -p tcp --dport "$p" -j ACCEPT || true
  done
  echo "iptables INPUT dport rules added (Gradio/API, if iptables present)."
}

open_ports_dash() {
  # Open API (8010) and Dash UI ports (8050/8051) only
  if systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --zone=public --add-port=8010/tcp --permanent || true
    sudo firewall-cmd --zone=public --add-port=${WEB_PORT:-8051}/tcp --permanent || true
    sudo firewall-cmd --reload || true
    echo "firewalld ports opened (Dash/API):"
    sudo firewall-cmd --list-ports || true
  else
    echo "firewalld not active; skipping firewall-cmd (Dash/API)"
  fi
  for p in 8010 "${WEB_PORT:-8051}"; do
    sudo iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -p tcp --dport "$p" -j ACCEPT || true
  done
  echo "iptables INPUT dport rules added (Dash/API, if iptables present)."
}

warn_port_conflicts() {
  echo "Checking for listeners on 7860/7861/${WEB_PORT:-8051}..."
  local listeners
  listeners="$(ss -ltnp | awk -v W="${WEB_PORT:-8051}" '$4 ~ ":"W"$" || $4 ~ /:(7860|7861)$/' || true)"
  if [[ -n "${listeners}" ]]; then
    echo "WARNING: Other UI listeners detected on 7860/7861/8050/8051:"
    echo "${listeners}"
    echo "Tip: free the port with: sudo fuser -k 7860/tcp || sudo fuser -k 7861/tcp"
  fi
}



smoke_test() {
  echo "----- First-go Smoke Test (bounded) -----"
  set +e
  echo "Process checks:"
  pgrep -fa uvicorn || echo "uvicorn not found"
  pgrep -fa streamlit || echo "streamlit not found"
  echo

  echo "Listening ports (API=${API_PORT:-8010}, WEB=${WEB_PORT:-8051}, GRADIO=7860/7861):"
  ss -ltnp | awk -v A="${API_PORT:-8010}" -v W="${WEB_PORT:-8051}" 'NR==1 || $4 ~ ":"A"$" || $4 ~ ":"W"$" || $4 ~ /:(7860|7861)$/'
  echo

  # Detect active UI port (Gradio 7860/7861, Dash 8050/8051)
  UI_PORT=""
  if ss -ltnp | grep -q ":${WEB_PORT:-8051}"; then
    UI_PORT="${WEB_PORT:-8051}"
  elif ss -ltnp | grep -q ":7860"; then
    UI_PORT="7860"
  elif ss -ltnp | grep -q ":7861"; then
    UI_PORT="7861"
  fi
  echo "UI_PORT=${UI_PORT:-none}"

  # API readiness
  echo
  echo "API /ready (max 6s):"
  curl -sS --max-time 6 http://localhost:${API_PORT:-8010}/ready | jq -c . || echo "API /ready failed"

  # API sample GET /recipe
  echo
  echo "API sample GET /recipe (max 12s):"
  curl -sS --max-time 12 "http://localhost:${API_PORT:-8010}${API_BASE_PATH:-/api/v1}/recipe?cuisine=Mexican&dietary=vegan" \
    | jq '{ok:(.recipe!=null), ingredients_len: ((.ingredients // []) | length), products_preview: ((.products // []) | .[0:2] | map({displayName, price}))}' \
    || echo "API sample failed"

  # UI GET /
  if [[ -n "${UI_PORT}" ]]; then
    echo
    echo "UI GET / (max 6s):"
    code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 "http://localhost:${UI_PORT}/")"
    echo "http://localhost:${UI_PORT}/ -> ${code}"
  fi

  # External hint
  PUB_IP="$(curl -s --max-time 3 https://ifconfig.me 2>/dev/null || printf '')"
  echo
  echo "Public IP: ${PUB_IP:-unknown}"
  if [[ -n "${UI_PORT}" && -n "${PUB_IP}" ]]; then
    echo "External UI HEAD hint:"
    curl -sI --max-time 6 "http://${PUB_IP}:${UI_PORT}/" | head -n 1 || true
  fi
  echo "----- Smoke Test complete -----"
  set -e
}

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

echo "Memory bank updated with first-go run learnings."

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

echo "Memory bank updated with Woolworths images/prices learnings."

# Append GenAI read-timeout guidance (300s) and mirror into .clinerules
if [[ -d "${DEST}/memory-bank" ]]; then
  cat >> "${DEST}/memory-bank/systemPatterns.md" << 'EOF'
## Learnings 2025-12-19 — Recipe endpoint read timeout (300s)

- GenAI-backed recipe generation can take time; clients and gateways should allow up to 300 seconds for the response.
- Defaults across the workshop:
  - Streamlit: STREAMLIT_API_TIMEOUT (recommended ≥ 300s)
  - Gradio: GRADIO_API_TIMEOUT=300
  - Dash: DASH_API_TIMEOUT=300
  - API Gateway: APIGW_READ_TIMEOUT=300 (applied to /api/v1 routes)
- Keep /health and /ready with short timeouts; only recipe endpoints need long read timeouts.
EOF
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/systemPatterns.md" "${DEST}/.clinerules/02-system-patterns.md" || true
fi

# Append Container RP signer + redeploy learnings (2025-12-18) and mirror to .clinerules
if [[ -d "${DEST}/memory-bank" ]]; then
  # memory-bank/containerStandards.md
  cat >> "${DEST}/memory-bank/containerStandards.md" << 'EOF'
## Learnings 2025-12-18 — Container RP signer and redeploy discipline

Symptoms observed
- Health endpoint (/health) OK in CI, but /ready and /recipe hung until timeout.
- Another CI in the same subnet worked fine → not a network issue.

Root cause
- The backend used InstancePrincipalsSecurityTokenSigner() inside a container instance. CI requires Resource Principals.

Standards (non‑negotiable)
- In containers (OCI CI/OKE/Functions), detect Resource Principals via:
  - os.getenv("OCI_RESOURCE_PRINCIPAL_VERSION")
  - If present → signer = get_resource_principals_signer()
  - Else → signer = InstancePrincipalsSecurityTokenSigner() (on OCI Compute)
- Keep request shape/response parsing identical per GenAI Standard.
- /ready must probe signer quickly (READY_SIGNER_TIMEOUT ~0.3s) and never block the app.
- After code changes: always rebuild/push the image, then delete-then-recreate the CI to pick up the new digest (immutable), which may yield a new private IP.

Verification
- curl -s http://<IP>:8000/health | jq
- curl -s http://<IP>:8000/ready | jq
- curl -s "http://<IP>:8000$API_BASE_PATH/recipe" | jq
- To reduce latency for a quick check: WOOL_TOTAL_TIMEOUT=0 (skips external product selection); re-enable bounded selection for images/prices.

CI shape/capacity reminder
- If CI.Standard.A1.Flex is OutOfCapacity, switch to CI.Standard.E4.Flex in workshop-config.yaml (config‑driven). Multi‑AD fallback remains recommended.
EOF

  # memory-bank/genaiStandards.md (explicit signer rule and example)
  cat >> "${DEST}/memory-bank/genaiStandards.md" << 'EOF'
## Learnings 2025-12-18 — GenAI signer in containers (Resource Principals)

- In containers, obtain signer via get_resource_principals_signer() when OCI_RESOURCE_PRINCIPAL_VERSION is set; otherwise use InstancePrincipalsSecurityTokenSigner() on OCI Compute.
- Keep ChatDetails/GenericChatRequest contract unchanged and parse response via:
  response.data.chat_response.choices[0].message.content[0].text

Python example:
```python
import os
from oci.generative_ai_inference import GenerativeAiInferenceClient
from oci.generative_ai_inference.models import ChatDetails, OnDemandServingMode, GenericChatRequest, Message, TextContent
from oci.auth.signers import InstancePrincipalsSecurityTokenSigner, get_resource_principals_signer

def make_client(settings):
    signer = get_resource_principals_signer() if os.getenv("OCI_RESOURCE_PRINCIPAL_VERSION") else InstancePrincipalsSecurityTokenSigner()
    return GenerativeAiInferenceClient(config={}, signer=signer, service_endpoint=settings.oci.service_endpoint)
```
EOF

  # Mirror into .clinerules
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/containerStandards.md" "${DEST}/.clinerules/08-container-standards.md" || true
  cp -f "${DEST}/memory-bank/genaiStandards.md" "${DEST}/.clinerules/05-genai-service-standard.md" || true
fi

# Append Dash CI first-go learnings (2025-12-18): config discovery & packaging; mirror into .clinerules
if [[ -d "${DEST}/memory-bank" ]]; then
  cat >> "${DEST}/memory-bank/dashStandards.md" << 'EOF'
## Learnings 2025-12-18 — Dash CI first-go RCA (config discovery & packaging)

Symptoms
- Dash container crashed on first start with FileNotFoundError: 'workshop-config.yaml'.

Root cause
- The app’s config discovery expects WORKSHOP_CONFIG_PATH or the standard container path /app/config.yaml. The image did not include the config file.

Standards (non‑negotiable)
1) Package config into the Dash image:
   - Dockerfile must include:
     COPY workshop-config.yaml /app/config.yaml
2) Optional runtime guard:
   - Set WORKSHOP_CONFIG_PATH=/app/config.yaml in CI env.
3) Always set API_BASE_URL in CI env to your backend (e.g., http://172.0.30.181:8000/api/v1) to guarantee first‑go success even if config parsing is delayed.

CI robustness
- Choose a random privateIp from the subnet CIDR; on “already in use”, retry without privateIp for auto‑assign.
- Enumerate ADs and fallback on OutOfCapacity.
- When listing CIs, use robust jq for hyphenated keys and array/.data shapes:
  (."display-name" // .displayName) and (if type=="array" then .[] else .data[] end)
EOF

  # Also record the CI script hardening in systemPatterns for infra repeatability
  cat >> "${DEST}/memory-bank/systemPatterns.md" << 'EOF'
## Learnings 2025-12-18 — Dash CI create robustness

- Package workshop-config.yaml into the image at /app/config.yaml (or set WORKSHOP_CONFIG_PATH) so config discovery works in containers.
- Set API_BASE_URL in CI env to point at the backend (http://172.0.30.181:8000/api/v1) for first‑go success.
- Pick random privateIp within the subnet; if conflict, retry with auto‑assign (no privateIp).
- Use jq with (."display-name" // .displayName) and support array vs .data when filtering CI lists.
- Continue to use multi‑AD fallback for capacity.
EOF

  # Mirror to .clinerules for enforcement
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/dashStandards.md" "${DEST}/.clinerules/13-dash-app-standard.md" || true
  cp -f "${DEST}/memory-bank/systemPatterns.md" "${DEST}/.clinerules/02-system-patterns.md" || true
fi

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

# Append Dash 3.x run API + Callback RCA (2025-12-12) and mirror to .clinerules

# Scaffold recipe-dash-app (baseline UI per standards; repeatable)
scaffold_dash_ui() {
  local dest_dir="${DEST}/recipe-dash-app"
  mkdir -p "${dest_dir}"

  # app.py (full baseline from standards)
  cat > "${dest_dir}/app.py" << 'EOF'
import os
import re
import json
import html as pyhtml
from urllib.parse import urlparse
from typing import Any, Dict, List, Optional, Tuple

import requests
from dash import Dash, dcc, html, Input, Output, State, callback, ALL
from dash.exceptions import PreventUpdate
import argparse
import dash_bootstrap_components as dbc

# Defaults (mirror workshop-config.yaml)
DEFAULT_API_PORT = int(os.getenv("API_PORT", "8010"))
DEFAULT_API_BASE_PATH = os.getenv("API_BASE_PATH", "/api/v1")
DEFAULT_BASE_URL = os.getenv(
    "API_BASE_URL",
    f"http://localhost:{DEFAULT_API_PORT}{DEFAULT_API_BASE_PATH}",
).rstrip("/")

DASH_API_TIMEOUT = int(os.getenv("DASH_API_TIMEOUT", "300"))

# UI tunables
IMAGE_WIDTH_SUGGESTION = 360
MAX_ING_BUTTONS = 12
MAX_PRODUCT_CARDS = 6

# --------------------------------------------------------------------- Helpers
def normalize_base_url(url: str) -> str:
    url = (url or "").strip()
    if not url:
        return DEFAULT_BASE_URL
    return url.rstrip("/")

def derive_health_url_from_base(api_base_url: str) -> str:
    api_base_url = normalize_base_url(api_base_url)
    parsed = urlparse(api_base_url)
    scheme = parsed.scheme or "http"
    netloc = parsed.netloc
    if not netloc:
        guess = api_base_url
        if not (guess.startswith("http://") or guess.startswith("https://")):
            host_port, *_ = guess.split("/", 1)
            netloc = host_port
            scheme = "http"
    if not netloc:
        netloc = f"localhost:{DEFAULT_API_PORT}"
    return f"{scheme}://{netloc}/health"

def request_timeout() -> int:
    return DASH_API_TIMEOUT

def parse_last_json(s: Optional[str]) -> Dict[str, Any]:
    if not s:
        return {}
    try:
        v = json.loads(s)
        return v if isinstance(v, dict) else {}
    except Exception:
        return {}

# ---------------------------- Text normalization (reasoning and recipe parsing)
ZW_CHARS = re.compile(r"[\u200b\u200c\u200d\ufeff]")
NBSP = re.compile(r"\u00a0")
MULTISPACE = re.compile(r"\s+")

def normalize_reasoning(txt: Optional[str]) -> str:
    if not txt:
        return ""
    s = str(txt)
    s = ZW_CHARS.sub("", s)
    s = NBSP.sub(" ", s)
    s = MULTISPACE.sub(" ", s)
    s = re.sub(r"\s+([,.;:!?])", r"\1", s)
    s = re.sub(r"([,.;:!?])(?!\s)", r"\1 ", s)
    return s.strip()

def extract_title_body(recipe_text: Optional[str]) -> Tuple[str, str]:
    if not recipe_text:
        return ("Recipe", "")
    text = str(recipe_text).replace("\r\n", "\n").strip()
    if not text:
        return ("Recipe", "")
    lines = text.split("\n")
    for idx, line in enumerate(lines):
        if line.strip():
            title = re.sub(r"^\s*#+\s*", "", line).strip() or "Recipe"
            body = "\n".join(lines[idx + 1 :]).strip()
            return (title, body)
    return ("Recipe", "")

def ensure_steps_heading(body: str) -> str:
    if not body:
        return ""
    text = body.replace("\r\n", "\n")
    if re.search(r'(?im)^\s*(?:#{2,6}\s*Steps\b|[*_]{2}\s*Steps\s*[*_]{2}|Steps\s*:)\s*$', text):
        return body
    m = re.search(r'(?m)^(?:\s*\d+\s*[\.\):]\s+)', text)
    if not m:
        return body
    idx = m.start()
    prefix = text[:idx].rstrip()
    suffix = text[idx:]
    return f"{prefix}\n\n#### Steps\n{suffix}"

# -------------------------------------------------------------- Image helpers
def prefer_large(url: Optional[str]) -> Optional[str]:
    if not url:
        return None
    s = str(url).strip()
    if not s:
        return None
    if s.startswith("//"):
        s = "https:" + s
    if s.startswith("/content/wowproductimages/"):
        s = "https://www.woolworths.com.au" + s
    s = re.sub(r"/(small|Small|medium|Medium)/", "/large/", s)
    return s

# --------------------------------------------------------------- API clients
def _safe_text(resp: requests.Response) -> str:
    try:
        return resp.text
    except Exception:
        return "<no body>"

def call_recipe_post(api_base_url: str, cuisine: Optional[str], dietary: Optional[str]) -> Dict[str, Any]:
    api = normalize_base_url(api_base_url)
    url = f"{api}/recipe"
    payload: Dict[str, Any] = {}
    if cuisine and cuisine.strip():
        payload["cuisine"] = cuisine.strip()
    if dietary and dietary.strip():
        payload["dietary"] = dietary.strip()
    try:
        r = requests.post(url, json=payload, timeout=request_timeout())
        return r.json() if r.ok else {"error": f"HTTP {r.status_code}", "body": _safe_text(r)}
    except Exception as e:
        return {"error": f"POST failed: {e.__class__.__name__}: {e}"}

def call_recipe_get(api_base_url: str, cuisine: Optional[str], dietary: Optional[str]) -> Dict[str, Any]:
    api = normalize_base_url(api_base_url)
    url = f"{api}/recipe"
    params: Dict[str, Any] = {}
    if cuisine and cuisine.strip():
        params["cuisine"] = cuisine.strip()
    if dietary and dietary.strip():
        params["dietary"] = dietary.strip()
    try:
        r = requests.get(url, params=params, timeout=request_timeout())
        return r.json() if r.ok else {"error": f"HTTP {r.status_code}", "body": _safe_text(r)}
    except Exception as e:
        return {"error": f"GET failed: {e.__class__.__name__}: {e}"}

def test_api_health(api_base_url: str) -> str:
    health_url = derive_health_url_from_base(api_base_url)
    try:
        r = requests.get(health_url, timeout=10)
        if r.ok:
            try:
                j = r.json()
                return f"✅ API healthy at {health_url}\n\n```\n{json.dumps(j, indent=2)}\n```"
            except Exception:
                return f"✅ API healthy at {health_url}\n\n(status {r.status_code})"
        else:
            return f"⚠️ API responded with HTTP {r.status_code} at {health_url}\n\n```\n{_safe_text(r)}\n```"
    except Exception as e:
        return f"❌ Failed to reach {health_url}: {e.__class__.__name__}: {e}"

# --------------------------------------------------------------- Cart helpers
def render_cart(cart: list) -> str:
    total = 0.0
    items = []
    if isinstance(cart, list):
        for item in cart:
            name = item.get("name") or "Item"
            price = item.get("price")
            if isinstance(price, (int, float)) and price > 0:
                total += float(price)
                items.append(f"- {pyhtml.escape(str(name))} — ${float(price):.2f}")
            else:
                items.append(f"- {pyhtml.escape(str(name))}")
    if not items:
        return "**Total:** $0.00"
    return "\n".join([f"**Total:** ${total:.2f}", ""] + items)

def model_caption(last: Optional[Dict[str, Any]]) -> str:
    if not last or not isinstance(last, dict):
        return ""
    bits = []
    for k in ("model", "cuisine", "dietary"):
        v = last.get(k)
        if v:
            bits.append(f"{k}: {pyhtml.escape(str(v))}")
    return " · ".join(bits)

# --------------------------------------------------------------------------- UI
app = Dash(__name__, external_stylesheets=[dbc.themes.LUX])

# Custom CSS for modern styling

app.index_string = '''
<!DOCTYPE html>
<html>
    <head>
        {%metas%}
        <title>What's for Dinner?</title>
        {%favicon%}
        {%css%}
        <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
        <style>
            :root {
                --primary: #2563eb;
                --secondary: #475569;
                --accent: #3b82f6;
                --background: #f9fafb;
                --text: #1e293b;
                --muted: #64748b;
                --card-bg: white;
                --shadow: rgba(0,0,0,0.04);
            }
            body {
                font-family: 'Inter', sans-serif;
                background: var(--background);
                color: var(--text);
                line-height: 1.6;
            }
            .container {
                max-width: 1440px !important;
                padding: 2rem 1rem;
            }
            .hero {
                background: linear-gradient(135deg, #0ea5e9 0%, #2563eb 100%);
                color: white;
                padding: 4rem 2rem;
                border-radius: 24px;
                margin-bottom: 3rem;
                text-align: center;
                box-shadow: 0 4px 24px rgba(0,0,0,0.1);
            }
            .hero h1 {
                font-size: 3rem;
                font-weight: 700;
                margin-bottom: 1rem;
            }
            .hero p {
                font-size: 1.25rem;
                color: rgba(255,255,255,0.95);
            }
            .card {
                border: none;
                border-radius: 16px;
                box-shadow: 0 4px 12px var(--shadow);
                transition: transform 0.3s ease, box-shadow 0.3s ease;
            }
            .card:hover {
                transform: translateY(-5px);
                box-shadow: 0 8px 24px var(--shadow);
            }
            .btn-primary {
                background: var(--primary);
                border: none;
                border-radius: 8px;
                padding: 0.75rem 1.5rem;
                font-weight: 600;
                transition: all 0.3s ease;
            }
            .btn-primary:hover {
                background: #1d4ed8;
                transform: translateY(-2px);
            }
            .btn-secondary {
                background: #f1f5f9;
                color: var(--secondary);
                border: 1px solid #e2e8f0;
                border-radius: 8px;
                padding: 0.75rem 1.5rem;
                font-weight: 600;
                transition: all 0.3s ease;
            }
            .btn-secondary:hover {
                background: #e2e8f0;
            }
            .section-divider {
                font-size: 1.25rem;
                font-weight: 600;
                color: var(--accent);
                margin-bottom: 1.5rem;
                padding-bottom: 0.5rem;
                border-bottom: 2px solid #dbeafe;
            }
            .rounded-pill {
                background: #eff6ff;
                color: var(--accent);
                border-radius: 50rem;
                padding: 0.5rem 1rem;
                margin: 0.25rem;
                transition: all 0.3s ease;
            }
            .rounded-pill:hover {
                background: #bfdbfe;
                transform: translateY(-2px);
            }
            img {
                border-radius: 12px;
                transition: transform 0.3s ease;
            }
            img:hover {
                transform: scale(1.05);
            }
            .debug-pre {
                background: #f8f9fa;
                border-radius: 12px;
                padding: 1.5rem;
                font-family: monospace;
                max-height: 400px;
                overflow: auto;
                box-shadow: inset 0 1px 3px rgba(0,0,0,0.05);
            }
            .cart-item {
                display: flex;
                justify-content: space-between;
                align-items: center;
                background: #f8fafc;
                border-radius: 8px;
                padding: 0.75rem 1rem;
                margin-bottom: 0.75rem;
                box-shadow: 0 1px 2px rgba(0,0,0,0.05);
            }
            .cart-total {
                font-size: 1.25rem;
                font-weight: 700;
                color: var(--accent);
                text-align: right;
                margin-top: 1rem;
            }
        </style>
    </head>
    <body>
        {%app_entry%}
        <footer>
            {%config%}
            {%scripts%}
            {%renderer%}
        </footer>
    </body>
</html>
'''

app.layout = dbc.Container([
    dcc.Store(id='store-cart', data=[]),
    dcc.Store(id='store-last', data={}),
    dcc.Store(id='debug-collapse', data=False),

    # Hero header
    dbc.Row([
        dbc.Col(
            html.Div([
                html.H1("What's for Dinner?", className="text-center mb-1"),
                html.P("Your AI-powered recipe generator with smart shopping suggestions", className="text-center")
            ], className="hero card p-5")
        )
    ], className="mb-5", justify="center"),

    dcc.Loading(id='page-loading', type='circle', fullscreen=True, children=[
        dbc.Row([
            # Left: Settings sidebar (card)
        dbc.Col([
            html.H4("🍴 Your Preferences", className="section-divider"),
            html.Div(id='api-env-info') if "API_BASE_URL" in os.environ else None,
            html.Label("Cuisine Type", className="form-label fw-semibold"),
            dcc.Dropdown(
                id='cuisine-sel',
                options=[{'label': c, 'value': c} for c in ["", "Italian", "Mexican", "Indian", "Chinese", "Thai", "Greek", "Other..."]],
                value="",
                className="mb-3",
                placeholder="Select cuisine"
            ),
            dcc.Input(id='cuisine-other', type='text', placeholder="Custom cuisine", className="form-control mb-3", style={'display': 'none'}),
            html.Label("Dietary Requirements", className="form-label fw-semibold"),
            dcc.Dropdown(
                id='dietary-sel',
                options=[{'label': c, 'value': c} for c in ["", "vegetarian", "vegan", "gluten-free", "keto", "pescatarian", "Other..."]],
                value="",
                className="mb-3",
                placeholder="Select dietary"
            ),
            dcc.Input(id='dietary-other', type='text', placeholder="Custom dietary", className="form-control mb-3", style={'display': 'none'}),
            dbc.Row([
                dbc.Col(
                    dcc.Loading(
                        id="generate-loading",
                        type="circle",
                        children=html.Button("Generate", id='generate-btn', className="btn btn-primary w-100 mb-2")
                    )
                ),
                dbc.Col(
                    dcc.Loading(
                        id="surprise-loading",
                        type="circle",
                        children=html.Button("Surprise me", id='surprise-btn', className="btn btn-secondary w-100")
                    )
                )
            ], className="g-2"),
            dcc.Input(
                id='api-input',
                type='text',
                value=DEFAULT_BASE_URL,
                placeholder="API Base URL",
                className="form-control mt-3"
            ),
            html.Button("Test API", id='test-btn', className="btn btn-secondary mt-3 w-100"),
            dcc.Markdown(id='test-out', className="mt-2 text-muted")
        ], width=3, class_name="card p-4"),

        # Center: Main content (cards)
        dbc.Col([
            # Recipe card
            dcc.Loading(
                children=html.Div([
                    html.Div("Recipe", className="section-divider"),
                    dcc.Markdown(id='meta-md', className="text-muted mb-3"),
                    dcc.Markdown(id='title-md', className="h3 mb-3"),
                    dcc.Markdown(id='body-md')
                ], className="card p-4 mb-4"),
                type="circle"
            ),

            # Ingredients card
            dcc.Loading(
                children=html.Div([
                    html.Div("Ingredients", className="section-divider"),
                    dcc.Markdown(id='ingredients-info', children="Use Generate/Surprise to fetch a recipe.", className="mb-3 text-muted"),
                    html.Div(id='ingredients-buttons', className="d-flex flex-wrap gap-2")
                ], className="card p-4 mb-4"),
                type="circle"
            ),

            # Product Suggestions card
            dcc.Loading(
                children=html.Div([
                    html.Div("Product Suggestions", className="section-divider"),
                    html.Div(id='products-cards', className="row g-4")
                ], className="card p-4 mb-4"),
                type="circle"
            ),

            # Hidden dummies for pattern-matching
            html.Div(id={'type': 'dynamic-ing-btn', 'index': -1}, style={'display': 'none'}),
            html.Div(id={'type': 'dynamic-prod-btn', 'index': -1}, style={'display': 'none'})
        ], width=6),

        # Right: Shopping Cart (sticky card)
        dbc.Col([
            html.Div("Shopping Cart", className="section-divider"),
            dcc.Loading(children=dcc.Markdown(id='cart-md', children="Cart is empty."), type="circle"),
            html.Button("Clear cart", id='clear-btn', className="btn btn-secondary mt-3 w-100")
        ], width=3, class_name="card p-4", style={"position": "sticky", "top": "2rem"})
    ], className="g-4"),
    ]),

    # Collapsible Debug section at bottom
    html.Div([
        html.Button("Toggle Debug API Output", id='toggle-debug', className="btn btn-link mt-4 w-100 text-left"),
        dbc.Collapse(
            html.Pre(id='debug-json', className="debug-pre"),
            id='debug-collapse-container',
            is_open=False
        )
    ], className="mt-5 card p-4")
], fluid=True, className="py-5")

# Callbacks
from dash import callback_context

@app.callback(
    Output('api-input', 'value'),
    Input('api-input', 'value')
)
def on_api_change(new_api):
    return normalize_base_url(new_api)

@app.callback(
    Output('cuisine-other', 'style'),
    Input('cuisine-sel', 'value')
)
def on_cuisine_sel(sel):
    return {'display': 'block'} if sel == "Other..." else {'display': 'none'}

@app.callback(
    Output('dietary-other', 'style'),
    Input('dietary-sel', 'value')
)
def on_dietary_sel(sel):
    return {'display': 'block'} if sel == "Other..." else {'display': 'none'}

@app.callback(
    Output('test-out', 'children'),
    Input('test-btn', 'n_clicks'),
    State('api-input', 'value'),
    prevent_initial_call=True
)
def test_api(n, api):
    return test_api_health(api)

@app.callback(
    [Output('store-last', 'data'),
     Output('debug-json', 'children'),
     Output('meta-md', 'children'),
     Output('title-md', 'children'),
     Output('body-md', 'children'),
     Output('ingredients-info', 'children'),
     Output('ingredients-buttons', 'children'),
     Output('products-cards', 'children'),
     Output('cart-md', 'children', allow_duplicate=True)],
    Input('generate-btn', 'n_clicks'),
    [State('api-input', 'value'),
     State('cuisine-sel', 'value'),
     State('cuisine-other', 'value'),
     State('dietary-sel', 'value'),
     State('dietary-other', 'value'),
     State('store-cart', 'data')],
    prevent_initial_call=True
)
def do_generate(n, api, cuisine_sel, cuisine_other, dietary_sel, dietary_other, cart):
    cuisine = cuisine_other if cuisine_sel == "Other..." else cuisine_sel
    dietary = dietary_other if dietary_sel == "Other..." else dietary_sel
    result = call_recipe_post(api, cuisine or None, dietary or None) or {}
    last = result
    debug = json.dumps(result, indent=2)
    meta = model_caption(last)
    title, body = extract_title_body(last.get("recipe"))
    body = ensure_steps_heading(body)
    ingredients = last.get("ingredients", [])
    ingredients_info = "" if ingredients else "No parsed ingredients found."
    ing_buttons = [
        html.Button(ing, id={'type': 'dynamic-ing-btn', 'index': i}, className="rounded-pill", n_clicks=0) 
        for i, ing in enumerate(ingredients[:MAX_ING_BUTTONS])
    ]
    products = last.get("products", [])[:MAX_PRODUCT_CARDS]
    products_cards = []
    for i in range(0, len(products), 3):  # 3 cards per row for better spacing
        cols = []
        for j in range(3):
            if i + j >= len(products):
                break
            p = products[i + j]
            card = dbc.Card([
                dbc.CardImg(src=prefer_large(p.get("image")), top=True, style={"height": "200px", "objectFit": "cover", "borderRadius": "8px 8px 0 0"}),
                dbc.CardBody([
                    html.H5(p.get("displayName", "Product"), className="card-title mb-2"),
                    html.P(f"Price: ${p.get('price', 0):.2f}" if p.get("price") else "Price: —", className="card-text text-primary font-weight-bold"),
                    html.P(normalize_reasoning(p.get("reasoning", "")), className="card-text small text-muted")
                ], className="p-3"),
                dbc.CardFooter(html.Button("Add to cart", id={'type': 'dynamic-prod-btn', 'index': i+j}, className="btn btn-primary w-100", n_clicks=0), className="p-0 border-0")
            ], className="h-100 shadow-sm")
            cols.append(dbc.Col(card, width=4))
        products_cards.append(dbc.Row(cols, className="g-4 mb-4"))
    cart_md = render_cart(cart)
    return last, debug, meta, f"### {title}", body, ingredients_info, ing_buttons, products_cards, cart_md

@app.callback(
    [Output('store-last', 'data', allow_duplicate=True),
     Output('debug-json', 'children', allow_duplicate=True),
     Output('meta-md', 'children', allow_duplicate=True),
     Output('title-md', 'children', allow_duplicate=True),
     Output('body-md', 'children', allow_duplicate=True),
     Output('ingredients-info', 'children', allow_duplicate=True),
     Output('ingredients-buttons', 'children', allow_duplicate=True),
     Output('products-cards', 'children', allow_duplicate=True),
     Output('cart-md', 'children', allow_duplicate=True)],
    Input('surprise-btn', 'n_clicks'),
    [State('api-input', 'value'),
     State('store-cart', 'data')],
    prevent_initial_call=True
)
def do_surprise(n, api, cart):
    result = call_recipe_get(api, None, None) or {}
    last = result
    debug = json.dumps(result, indent=2)
    meta = model_caption(last)
    title, body = extract_title_body(last.get("recipe"))
    body = ensure_steps_heading(body)
    ingredients = last.get("ingredients", [])
    ingredients_info = "" if ingredients else "No parsed ingredients found."
    ing_buttons = [
        html.Button(ing, id={'type': 'dynamic-ing-btn', 'index': i}, className="rounded-pill", n_clicks=0) 
        for i, ing in enumerate(ingredients[:MAX_ING_BUTTONS])
    ]
    products = last.get("products", [])[:MAX_PRODUCT_CARDS]
    products_cards = []
    for i in range(0, len(products), 3):  # 3 cards per row
        cols = []
        for j in range(3):
            if i + j >= len(products):
                break
            p = products[i + j]
            card = dbc.Card([
                dbc.CardImg(src=prefer_large(p.get("image")), top=True, style={"height": "200px", "objectFit": "cover", "borderRadius": "8px 8px 0 0"}),
                dbc.CardBody([
                    html.H5(p.get("displayName", "Product"), className="card-title mb-2"),
                    html.P(f"Price: ${p.get('price', 0):.2f}" if p.get("price") else "Price: —", className="card-text text-primary font-weight-bold"),
                    html.P(normalize_reasoning(p.get("reasoning", "")), className="card-text small text-muted")
                ], className="p-3"),
                dbc.CardFooter(html.Button("Add to cart", id={'type': 'dynamic-prod-btn', 'index': i+j}, className="btn btn-primary w-100", n_clicks=0), className="p-0 border-0")
            ], className="h-100 shadow-sm")
            cols.append(dbc.Col(card, width=4))
        products_cards.append(dbc.Row(cols, className="g-4 mb-4"))
    cart_md = render_cart(cart)
    return last, debug, meta, f"### {title}", body, ingredients_info, ing_buttons, products_cards, cart_md

@app.callback(
    Output('store-cart', 'data', allow_duplicate=True),
    Output('cart-md', 'children', allow_duplicate=True),
    Input('clear-btn', 'n_clicks'),
    State('store-cart', 'data'),
    prevent_initial_call=True
)
def clear_cart(n, cart):
    return [], "Cart is empty."

# Pattern-matching callback for dynamic ingredient buttons
@app.callback(
    [Output('store-cart', 'data', allow_duplicate=True),
     Output('cart-md', 'children', allow_duplicate=True)],
    Input({'type': 'dynamic-ing-btn', 'index': ALL}, 'n_clicks'),
    [State('store-last', 'data'),
     State('store-cart', 'data')],
    prevent_initial_call=True
)
def add_ingredient(n_clicks_list, last, cart):
    ctx = callback_context
    if not ctx.triggered:
        raise PreventUpdate
    triggered_id = ctx.triggered[0]['prop_id'].split('.')[0]
    triggered_dict = json.loads(triggered_id)
    idx = triggered_dict['index']
    ingredients = last.get("ingredients", [])
    if idx < len(ingredients):
        name = ingredients[idx]
        cart.append({"name": name, "source": "ingredient"})
    return cart, render_cart(cart)

# Pattern-matching callback for dynamic product buttons
@app.callback(
    [Output('store-cart', 'data', allow_duplicate=True),
     Output('cart-md', 'children', allow_duplicate=True)],
    Input({'type': 'dynamic-prod-btn', 'index': ALL}, 'n_clicks'),
    [State('store-last', 'data'),
     State('store-cart', 'data')],
    prevent_initial_call=True
)
def add_product(n_clicks_list, last, cart):
    ctx = callback_context
    if not ctx.triggered:
        raise PreventUpdate
    triggered_id = ctx.triggered[0]['prop_id'].split('.')[0]
    triggered_dict = json.loads(triggered_id)
    idx = triggered_dict['index']
    products = last.get("products", [])
    if idx < len(products):
        p = products[idx]
        name = p.get("displayName") or "Product"
        price = p.get("price")
        img = prefer_large(p.get("image"))
        cart.append({"name": name, "price": price, "image": img, "source": "product"})
    return cart, render_cart(cart)

@app.callback(
    Output('debug-collapse-container', 'is_open'),
    Input('toggle-debug', 'n_clicks'),
    State('debug-collapse-container', 'is_open'),
    prevent_initial_call=True
)
def toggle_debug(n, is_open):
    return not is_open

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8050)
    args = parser.parse_args()
    app.run(debug=True, port=args.port)
EOF

  # run.sh (baseline from standards)
  cat > "${dest_dir}/run.sh" << 'EOF'
#!/bin/bash

# Change to the script's directory
cd "$(dirname "$0")" || exit 1

# Ensure localhost is not proxied (prevents corporate proxy issues on localhost)
export NO_PROXY="127.0.0.1,localhost,.localhost"
export no_proxy="127.0.0.1,localhost,.localhost"

# Default ports (Dash standard: 8050, backup 8051)
DEFAULT_PORT=8050
BACKUP_PORT=8051

# Kill any process on the ports
echo "Killing any process bound to TCP ports $DEFAULT_PORT/$BACKUP_PORT (if any) ..."
sudo fuser -k ${DEFAULT_PORT}/tcp >/dev/null 2>&1 || true
sudo fuser -k ${BACKUP_PORT}/tcp >/dev/null 2>&1 || true

# Create venv if it doesn't exist
if [ ! -d ".venv-dash" ]; then
  echo "Creating virtual environment .venv-dash ..."
  python3 -m venv .venv-dash
fi

# Activate venv
source .venv-dash/bin/activate

# Upgrade pip and install requirements
echo "Upgrading pip and installing requirements ..."
python -m pip install --upgrade pip
pip install -r requirements.txt

# Default API Base URL from env or fallback
API_BASE_URL="${API_BASE_URL:-http://localhost:8010/api/v1}"
echo "Default API Base URL: $API_BASE_URL"
echo "Tip: You can override API_BASE_URL before running this script."

# Launch on default port, fallback to backup if busy
PORT=$DEFAULT_PORT
if ss -ltn | grep -q ":$PORT "; then
  PORT=$BACKUP_PORT
fi

echo "Launching What's for Dinner? on http://0.0.0.0:$PORT ..."
python app.py --port $PORT

# Optional: tail logs or verify
echo "--- HEAD check ---"
curl -sI http://localhost:$PORT/ | head -n 1
echo "--- tail serve.log ---"
# tail -f serve.log  # Uncomment if you have a log file
EOF

  chmod +x "${dest_dir}/run.sh"

  # requirements.txt (baseline from standards)
  cat > "${dest_dir}/requirements.txt" << 'EOF'
dash
dash-bootstrap-components
requests
EOF

  # allow_firewall.sh (adapted for Dash ports)
  cat > "${dest_dir}/allow_firewall.sh" << 'EOF'
#!/bin/bash

# Open Dash ports (8050/8051) and FastAPI (8010) for external access
# Uses firewalld if active, or iptables as fallback

if systemctl is-active --quiet firewalld; then
  sudo firewall-cmd --zone=public --add-port=8050/tcp --permanent || true
  sudo firewall-cmd --zone=public --add-port=8051/tcp --permanent || true
  sudo firewall-cmd --zone=public --add-port=8010/tcp --permanent || true
  sudo firewall-cmd --reload || true
  echo "firewalld ports opened (if available):"
  sudo firewall-cmd --list-ports || true
else
  echo "firewalld not active; using iptables fallback"
fi

for p in 8050 8051 8010; do
  sudo iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || sudo iptables -I INPUT -p tcp --dport "$p" -j ACCEPT || true
done
echo "iptables INPUT dport rules added (if iptables present)."

# Verification
echo "Local HEAD checks:"
for p in 8050 8051 8010; do
  curl -sI --max-time 3 "http://localhost:$p/" | head -n 1 || echo "No listener on $p"
done

PUB_IP="$(curl -s --max-time 3 https://ifconfig.me 2>/dev/null || printf 'unknown')"
echo "Public IP: ${PUB_IP}"
if [[ "${PUB_IP}" != "unknown" ]]; then
  echo "External HEAD hints:"
  for p in 8050 8051 8010; do
    curl -sI --max-time 3 "http://${PUB_IP}:$p/" | head -n 1 || echo "No external response on $p"
  done
fi
EOF

  chmod +x "${dest_dir}/allow_firewall.sh"
  echo "Scaffolded: recipe-dash-app/ (app.py, run.sh, requirements.txt, allow_firewall.sh)"
}

# Call to scaffold Dash UI (opt-in with -S only)
if [[ "${SCAFFOLD_UI}" -eq 1 ]]; then
  if [[ ! -d "${DEST}/recipe-dash-app" || "${FORCE}" -eq 1 ]]; then
    scaffold_dash_ui
  else
    echo "Exists (skipping): ${DEST}/recipe-dash-app (use -f to overwrite)"
  fi
else
  echo "UI scaffolding disabled (no -S). The workshop expects building the Dash UI from prompts + memory-bank + .clinerules."
fi
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

# Append Gradio App Standard and 2025-12-11 learnings (idempotent)
if [[ -d "${DEST}/memory-bank" ]]; then
  # Baseline Gradio App Standard (create if missing, or overwrite with -f)
  if [[ ! -f "${DEST}/memory-bank/gradioStandards.md" || "${FORCE}" -eq 1 ]]; then
    cat > "${DEST}/memory-bank/gradioStandards.md" << 'EOF'
# Gradio App Standard — UI, State, API Client, and Setup (Non‑Negotiable)

Purpose
- Provide a repeatable, minimal Gradio UI that pairs with the Recipe FastAPI backend.
- Sidebar for settings; center for recipe/ingredients/products; right for cart; Debug JSON at bottom.

Core contract
- Blocks(title="What's for Dinner?")
- Config discovery for default base URL: http://localhost:${api.port}${api.base_path}
- State: api base URL, last result, cart
- API client via requests with timeout GRADIO_API_TIMEOUT (default 300s)
- Controls: Cuisine/Dietary with “Other...”, Generate (POST) and Surprise me (GET)
- Recipe, Ingredients (chips), Product cards (image, price, reasoning), “Add to cart”
- Cart with running total; Clear cart; Debug JSON panel

Update API (Gradio 4.x)
- Use gr.update(...) for ALL component updates (Markdown/HTML/Button/Textbox/JSON).
- Do NOT call Component.update (HTML.update/Textbox.update/Button.update) — raises AttributeError on Gradio 4.x.

HTML Safety
- Prefer Python html.escape(...) for HTML text; avoid gradio.utils.sanitize_html (may not exist across versions).

UI Defaults
- Hide product “Add to cart” buttons until products exist; reveal via gr.update(visible=True) once data arrives.
- Click handlers’ function signatures must match inputs. Example: fn=lambda cart, last, i=idx: ..., inputs=[state_cart, state_last].

Port/run notes
- Choose 7860 by default; if busy, fall back to 7861. Set GRADIO_SERVER_PORT to the chosen port.
- Implement IPv4/IPv6 friendly busy check and open firewall for UI/API ports.

Compatibility (oauth import)
- With gradio>=4.44, pin huggingface_hub<1.0 to avoid oauth import errors (‘HfFolder’ missing).
  - Add line to requirements: huggingface_hub<1.0
EOF
    echo "Wrote: ${DEST}/memory-bank/gradioStandards.md"
  else
    echo "Exists (skipping): ${DEST}/memory-bank/gradioStandards.md (use -f to overwrite)"
  fi

  # Append latest Gradio learnings (once)
  if ! grep -q "Learnings 2025-12-11 — Gradio 4.x" "${DEST}/memory-bank/gradioStandards.md" 2>/dev/null; then
    cat >> "${DEST}/memory-bank/gradioStandards.md" << 'EOF'
## Learnings 2025-12-11 — Gradio 4.x update API, HTML escaping, and UI defaults

- Use gr.update(...) for all component updates. Do NOT use Component.update (e.g., HTML.update/Textbox.update/Button.update).
- Replace gradio.utils.sanitize_html with Python html.escape for safe rendering.
- Default hidden “Add to cart” buttons; reveal only when products are present via gr.update(visible=True).
- Event handlers must align with inputs: use fn=lambda cart, last, i=idx: ..., inputs=[state_cart, state_last].
- Set GRADIO_SERVER_PORT to the selected port and implement IPv4/IPv6-safe busy checks; fall back 7860 → 7861.
- For gradio>=4.44, add compatibility pin in UI requirements: huggingface_hub<1.0 to avoid oauth import errors.
EOF
  fi

  # Mirror into .clinerules for enforcement
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/gradioStandards.md" "${DEST}/.clinerules/12-gradio-app-standard.md" || true

  # Append Gradio First-go RCA and fixes (idempotent) and re-mirror
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
    cp -f "${DEST}/memory-bank/gradioStandards.md" "${DEST}/.clinerules/12-gradio-app-standard.md" || true
  fi

  # Optional: patch an existing Gradio UI requirements file with the compatibility pin
  if [[ -f "${DEST}/recipe-gradio-app/requirements.txt" ]]; then
    if ! grep -q '^huggingface_hub<1\.0' "${DEST}/recipe-gradio-app/requirements.txt"; then
      echo "huggingface_hub<1.0" >> "${DEST}/recipe-gradio-app/requirements.txt"
      echo "Patched: recipe-gradio-app/requirements.txt (added huggingface_hub<1.0)"
    fi
  fi
fi

# Append Systemd Quick Setup (2025-12-09): concise prompt to create/enable/start services
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

  # Mirror into .clinerules for enforcement
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/systemdStandards.md" "${DEST}/.clinerules/09-systemd-services.md" || true
fi

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
  "gradioStandards.md:12-gradio-app-standard.md"
  "dashStandards.md:13-dash-app-standard.md"
  "lbStandards.md:14-oci-lb-standards.md"
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
      "11-mcp-standards.md" \
      "12-gradio-app-standard.md" \
      "13-dash-app-standard.md" \
      "14-oci-lb-standards.md"
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
  compartment_ocid: "ocid1.compartment.oc1..xxxxxxxx"

llm:
  model_id: "xai.grok-4-fast-reasoning"  # Or other supported model
  temperature: 0.7
  top_p: 0.9
  max_tokens: 2000

api:
  base_path: "/api/v1"
  port: 8010

# Generic web interface (UI) configuration; default to Dash fallback port
web_interface:
  port: 8051

docker:
  registry: "syd.ocir.io/sdncspltazsk/recipe-api"
  tag: "latest"

deployment:
  container_instance_shape: "CI.Standard.E4.Flex"
  subnet_ocid: "ocid1.subnet.oc1..xxxxxxxx"
  private_ip: ""
  # For API Gateway and Load Balancer: set route_prefix, health_check_path, etc.

api_gateway:
  display_name: "vibe-api-public-gw"
  type: "PUBLIC"                   # PUBLIC (default) or PRIVATE
  subnet_id: "ocid1.subnet.oc1..xxxxxxxx"

# Generic website load balancer (replaces streamlit_lb/application_lb)
website_lb:
  display_name: "vibe-workshop-website-lb"
  shape: "flexible"
  is_public: true
  subnet_ids:
    - "ocid1.subnet.oc1..xxxxxxxx"
  listener_port: 80
  backend_host: ""        # Set to your VM's private IP if needed
  backend_port: 8051
  health_check_path: "/"
  health_check_protocol: "HTTP"
  health_check_port: 8051
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
# Friendly user prompts (non-technical) — idempotent
# -----------------------------------------------------------------------------
mkdir -p "${DEST}/prompts"
if [[ ! -f "${DEST}/prompts/friendly-dash.txt" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/prompts/friendly-dash.txt" << 'EOF'
Build a friendly plotty dash app called “What’s for Dinner?” under recipe-dash-app/. Use the Workshop Memory Bank and workshop-config.yaml to handle all the details quietly in the background (per Gradio App Standard). The app should:
- Let me choose cuisine and dietary options on the left with “Generate” (POST) and “Surprise me” (GET)
- Show the recipe, clickable ingredient chips (to add to cart), and product suggestions with prices and clear reasons
- Work out of the box with my running API; if the address isn’t known, let me set it in a textbox and include a quick Test API button
- Provide a command to run the app (and a backup port if the first is busy)
- Hide technical choices and implementation details; follow the Memory Bank, configuration, and .clinerules
- Create or use a virtual env for the dash UI
- Allow iptables and firewalld for dash and FastAPI ports and verify external access
- Show a Debug API Output panel at the bottom with the raw JSON response
EOF
  echo "Wrote: ${DEST}/prompts/friendly-dash.txt"
else
  echo "Exists (skipping): ${DEST}/prompts/friendly-dash.txt (use -f to overwrite)"
fi

# -----------------------------------------------------------------------------
# Defaults and helpers
# -----------------------------------------------------------------------------
if [[ ! -f "${DEST}/.env" || "${FORCE}" -eq 1 ]]; then
  cat > "${DEST}/.env" << 'EOF'
# API and UI
API_PORT=8010
API_BASE_PATH=/api/v1
GRADIO_PORT=7860
GRADIO_API_TIMEOUT=300
# API Gateway read timeout (seconds) — GenAI may take time; 300s recommended
APIGW_READ_TIMEOUT=300

# Woolworths selection and LLM reasoning (tuning knobs)
WOOL_TOTAL_TIMEOUT=30
WOOL_MAX_INGREDIENTS=all
WOOL_TOPK=2
WOOL_CONCURRENCY=5
WOOL_TIMEOUT=6.0
WOOL_PER_ING_TIMEOUT=300.0
WOOL_REASON_TIMEOUT=300.0
WOOL_REASON_CONCURRENCY=1
WOOL_REASON_MANDATORY=1
WOOL_REASON_TOPN=all
WOOL_CACHE_TTL=300
WOOLWORTHS_STORE_ID=

# Readiness/observability
READY_SIGNER_TIMEOUT=0.3
EOF
  echo "Wrote: ${DEST}/.env (defaults for API/UI and Woolworths/LLM tuning)"
else
  echo "Exists (skipping): ${DEST}/.env (use -f to overwrite)"
fi



# Verification helper to ensure Memory Bank and .clinerules are in place
verify_rules() {
  echo "Verifying Memory Bank and .clinerules..."
  local mb_dir="${DEST}/memory-bank"
  local cl_dir="${DEST}/.clinerules"
  local mb_required=(activeContext.md projectbrief.md systemPatterns.md techContext.md productContext.md genaiStandards.md woolworthsStandards.md streamlitStandards.md containerStandards.md systemdStandards.md devopsStandards.md mcpStandards.md gradioStandards.md dashStandards.md lbStandards.md)
  local cl_required=(00-active-context.md 01-project-brief.md 02-system-patterns.md 03-tech-context.md 04-product-context.md 05-genai-service-standard.md 06-woolworths-service-standard.md 07-streamlit-app-standard.md 08-container-standards.md 09-systemd-services.md 10-devops-standards.md 11-mcp-standards.md 12-gradio-app-standard.md 13-dash-app-standard.md 14-oci-lb-standards.md)
  local missing_mb=() missing_cl=()
  local count_mb=0 count_cl=0
  for f in "${mb_required[@]}"; do
    if [[ -f "${mb_dir}/${f}" ]]; then ((count_mb++)); else missing_mb+=("${f}"); fi
  done
  for f in "${cl_required[@]}"; do
    if [[ -f "${cl_dir}/${f}" ]]; then ((count_cl++)); else missing_cl+=("${f}"); fi
  done
  echo "Memory Bank files: ${count_mb}/${#mb_required[@]}"
  if (( ${#missing_mb[@]} )); then echo "Missing memory-bank files: ${missing_mb[*]}"; fi
  echo ".clinerules files: ${count_cl}/${#cl_required[@]}"
  if (( ${#missing_cl[@]} )); then echo "Missing .clinerules files: ${missing_cl[*]}"; fi
}

# Optional networking and port hygiene
if [[ "${OPEN_PORTS}" -eq 1 || "${OPEN_GRADIO_PORTS}" -eq 1 ]]; then
  open_ports_gradio
fi
if [[ "${OPEN_PORTS}" -eq 1 || "${OPEN_DASH_PORTS}" -eq 1 ]]; then
  open_ports_dash
fi
if [[ -n "${VERBOSE:-}" ]]; then
  warn_port_conflicts
fi
if [[ "${RUN_TESTS}" -eq 1 ]]; then
  smoke_test
fi

# Bootstrap script generation is disabled by policy.
# Guidance lives in memory-bank/ and .clinerules/ only.
true

verify_rules
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
echo "  export GRADIO_API_TIMEOUT=300  # Gradio client request timeout (seconds)"
echo "  export WOOL_REASON_MANDATORY=1  # enforce LLM reasoning for all ingredients by default"
echo "  export WOOL_REASON_TOPN=all     # explicit all-ingredients reasoning (ignored if MANDATORY=1)"
echo "  # optional store scoping for relevance:"
echo "  export WOOLWORTHS_STORE_ID=3024"
echo ""
echo "Frontend (Gradio) tips:"
echo "  recipe-gradio-app/run.sh  # tries 7860 then 7861"
echo "  export API_BASE_URL=http://localhost:$API_PORT$API_BASE_PATH  # or your API Gateway URL"
echo "  # The UI shows product suggestions and a Debug JSON panel at the bottom."
echo ""
echo "After building the API, ensure dependencies (includes httpx) are installed:"
echo "  pip install -r recipe-api/requirements.txt"
echo "  # Ensure httpx is present for Woolworths service (async search):"
echo "  ./.venv/bin/python -c 'import httpx' 2>/dev/null || ./.venv/bin/pip install httpx"
echo ""
echo "First run stability tips (Learning 2025-12-08):"
echo "  - Start uvicorn WITHOUT --reload to catch import errors deterministically:"
echo "      .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT"
echo "    Once imports succeed, you can add --reload for dev."
echo "  - For quick verification, skip external product selection to avoid long waits:"
echo "      WOOL_TOTAL_TIMEOUT=0 .venv/bin/python -m uvicorn recipe-api.app.main:app --host 0.0.0.0 --port $API_PORT"
echo "    Then re-enable selection with bounded timeouts:"
echo "      export WOOL_MAX_INGREDIENTS=2 WOOL_TOPK=2 WOOL_TIMEOUT=3 WOOL_PER_ING_TIMEOUT=8 WOOL_REASON_TIMEOUT=4 WOOL_TOTAL_TIMEOUT=8"
echo "  - Readiness must never block: signer is probed with a short timeout (READY_SIGNER_TIMEOUT, default 0.3s)."
echo "  - Curl tip: use '&' in query strings, not HTML-encoded '&'."
echo "  - If a previous dev server is bound to the port, free it: fuser -k $API_PORT/tcp"

echo ""
echo "---------------------------------------------"
echo "IMPORTANT: Systemd Absolute Path & Repeatable Startup Rule (Learning 2025-11-26)"
echo "---------------------------------------------"
echo "To reliably run FastAPI and Streamlit under systemd:"
echo "  1. All unit files MUST use absolute WorkingDirectory and EnvironmentFile values (no shell \$(pwd))."
echo "  2. Always run sudo systemctl daemon-reload, enable, and start after editing/creating unit files, not just copy."
echo "  3. Stop any manual dev servers before starting systemd services to avoid port conflicts (${API_PORT:-8010}/${STREAMLIT_PORT:-8501})."
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

# Append DevOps CLI first-go learnings (2025-12-19) and mirror to .clinerules
if [[ -d "${DEST}/memory-bank" ]]; then
  cat >> "${DEST}/memory-bank/devopsStandards.md" << 'EOF'
## Learnings 2025-12-19 — DevOps CLI first‑go RCA (pagination, JMESPath, repo/SCM readiness)

Root causes observed
- Pagination: devops/ons list commands returned partial results without --all → lookups failed.
- Hyphenated keys with jq: brittle parsing ("display-name") caused jq errors; prefer OCI CLI --query (JMESPath) or tolerant jq filters.
- Repo lifecycle: pushing before repository lifecycle-state ACTIVE caused "repository does not exist".
- SCM readiness: pushing immediately after repo create can fail; backoff with git ls-remote.
- SSH handshake: missing known_hosts entry for devops.scmservice.<region>.oci.oraclecloud.com caused interactive prompts or failures.
- Divergent histories: remote default content requires fetch+merge --allow-unrelated-histories before first push.

Standards added
- Always pass --all to list commands (devops project/repository list, ons topic list).
- Prefer OCI CLI JMESPath --query filters (escape "display-name" as '\"display-name\"' when needed). Use jq only with array/data tolerant filters.
- Wait until repo lifecycle-state is ACTIVE before attempting git push.
- Probe SCM readiness with git ls-remote origin using exponential backoff.
- Prime SSH known_hosts via: ssh-keyscan -H devops.scmservice.<region>.oci.oraclecloud.com >> ~/.ssh/known_hosts
- If remote main exists, git fetch origin main && git merge --allow-unrelated-histories origin/main before push.

Helper
- This setup script can export scripts/devops_bootstrap.sh with -V for a robust, repeatable DevOps provisioning + push flow (idempotent, SSH-first).
EOF
  # Mirror to .clinerules
  mkdir -p "${DEST}/.clinerules"
  cp -f "${DEST}/memory-bank/devopsStandards.md" "${DEST}/.clinerules/10-devops-standards.md" || true
fi

# -----------------------------------------------------------------------------
# Mirror memory bank into .clinerules and aggregate AGENTS.md
# -----------------------------------------------------------------------------