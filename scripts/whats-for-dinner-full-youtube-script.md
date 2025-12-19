Title: Build and Ship a GenAI Microservices App by Vibe Coding with Cline (Whats for Dinner?)
Host: Barjinder Singh (Sydney, Australia) - Oracle Cloud Architect - fluffyclouds.blog

Target length: 15-20 minutes
Format: Teleprompter-ready narration + on-screen cues + demo steps


00:00 - Cold open (hook)
Narration (energetic):
What if you could develop and deploy a GenAI microservices application just by describing what you want? Today, I am building Whats for Dinner? — a concept app that answers the daily question, whats for dinner? We will vibe code it end-to-end with Cline and Oracle Code Assist, wire in AI, ship a Plotly Dash UI, and validate everything. No mystery magic — just step-by-step natural language, strict standards, and production discipline.

On-screen:
- Montage: VS Code, Cline panel, terminal, browser with a recipe UI, checklist ticking off.
- Title card: Vibe Coding a GenAI Microservices App with Cline — By Barjinder Singh (fluffyclouds.blog) — Sydney, Australia


00:25 - Host intro + credibility
Narration:
Hey everyone, I’m Barjinder Singh from Sydney, Australia. I’m a Cloud Architect with Oracle and I write at fluffyclouds.blog. In this session, I’ll show you how I plan and ship a small but real GenAI app using Cline and Oracle Code Assist as the AI provider, with strong guardrails: Memory Bank, .clinerules, local MCP servers, and a strict Plan vs Act workflow.

On-screen lower-third:
Barjinder Singh — Oracle Cloud Architect — Sydney, Australia
fluffyclouds.blog  |  linkedin.com/in/barjinder-singh-48357555


00:45 - What we are building (Whats for Dinner?)
Narration:
The app is called Whats for Dinner? A tiny GenAI microservices application that:
- Generates dinner recipes with preferences like cuisine and dietary.
- Extracts an ingredients list for downstream processing.
- Optionally fetches Woolworths product suggestions with reasoning.
- Presents a friendly Plotly Dash UI.
- Can be run locally, as services, or containerized and fronted by API Gateway and Load Balancer.

On-screen:
- Show recipe-guide.html conceptual architecture box and diagram.
- Quick list of phases we’ll follow (Phase 1 to Phase 9) from the guide.


01:20 - How Cline works (fast primer)
Narration:
Cline is an AI developer that operates inside your environment with tools. It reads, searches, and edits files. It runs commands, launches a headless browser, and calls external tools via the Model Context Protocol. It always uses one tool per step, waits for your confirmation after each step, and adapts using your feedback.

Key ideas we will use:
- Plan Mode: explore, synthesize a plan, ask for sign-off.
- Act Mode: execute with tools step-by-step, wait for confirmation, summarize results.
- Memory Bank vs .clinerules: product intent and context vs enforced standards.
- Local MCP servers: plug your domain APIs into Cline.
- Model settings: pick a provider and tune knobs for reliability.

On-screen:
- Split slide: Plan Mode vs Act Mode.
- Bullet: one tool per step; confirmation required.


02:00 - Configure Cline provider and model settings (Oracle Code Assist)
Narration:
We’ll use Oracle Code Assist as the provider in Cline. In your Cline settings, select Oracle Code Assist, sign in with your Oracle customer account, and choose a balanced default model for code plus tool use. Keep temperature low for code tasks and increase slightly for ideation only.

Starter settings checklist:
- Provider: Oracle Code Assist
- Default model: a general-purpose code+tool model
- Temperature: 0.2 to 0.4 for code steps
- Max tool steps/task: 15 to 25 to prevent runaway loops
- Auto-approve: Off or strictly read-only operations
- Timeouts/retries: tuned for your network/MCP tools

On-screen:
- Cline settings panel quick walkthrough.
- Link: docs.cline.bot/introduction/welcome


02:40 - Memory Bank vs .clinerules (the guardrails)
Narration:
Cline reads two key sources before acting:
- Memory Bank: your project’s intent, active context, and progress. This is how I encode what we are building and why.
- .clinerules: house rules and non-negotiable standards. These enforce consistent API surfaces, logging patterns, container policies, deployment guardrails, and MCP expectations.

agent.md (optional) in the Memory Bank can define the assistant’s persona and priorities — for example: be strict about .clinerules, prefer surgical edits over full rewrites, and maintain a running task checklist.

On-screen:
- Simple directory sketch:
  memory-bank/
    agent.md, standards.md, progress.md
  .clinerules/
    10-devops-standards.md, 11-mcp-standards.md, 99-style.md


03:20 - Our run of show uses recipe-guide.html
Narration:
Everything I do today follows a written guide: recipe-guide.html. It lays out nine phases, gives prompts you can copy into Cline, provides architecture diagrams, and includes verification commands and optional production hardening.

We’ll follow the guide’s flow:
0) One-time setup
1) FastAPI GET recipe
2) POST + health + readiness
3) Ingredients extraction
4) Woolworths product integration with reasoning
5) Plotly Dash app
6) systemd services
7) Local MCP server for the recipe API
8) Optional: Containers, OCI DevOps, API Gateway, Load Balancer
9) End-to-end validation

On-screen:
- Scroll through recipe-guide.html TOC and show each phase heading.


03:55 - Phase 0 - One-time setup (provided by instructor)
Narration:
We start with the one-time setup. The guide includes a script to scaffold the Memory Bank, .clinerules, and workshop-config.yaml. After running it, open workshop-config.yaml and fill in your tenancy values. We keep configs external and never hardcode secrets or regions.

On-screen steps:
- Run setup_ws_dash.sh
- Open workshop-config.yaml and edit only placeholders.
- Show the warn and tip boxes from the guide.


04:25 - Switch to Cline — quick explainer of workflow
Narration:
Here’s how I’ll run the build. First, we align in Plan Mode: Cline reads files, explores the project, and I confirm the plan. Then I switch to Act Mode, and Cline will apply changes step-by-step using tools like replace_in_file or write_to_file, run verification commands, and wait for my approval at each step.

On-screen:
- Cline panel: Plan Mode summary, then toggle to Act Mode when ready.


04:45 - Phase 1 — Build a FastAPI AI application (GET /api/v1/recipe)
Narration:
We’ll start with a minimal FastAPI backend that returns a random recipe, driven by our Memory Bank and config. In the guide, there’s a prompt block for Phase 1. Paste that into Cline. Let it scaffold the API, wire the GenAI call, and output a uvicorn command.

Verification (terminal):
curl -s "http://localhost:8010/api/v1/recipe" | jq

Acceptance:
- A JSON object that includes a recipe with title, ingredients, and instructions.

On-screen:
- Paste Phase 1 prompt from the guide into Cline.
- Approve steps, then run the uvicorn command it prints.
- Show curl success.


05:40 - Phase 2 — Add POST /recipe, health and readiness
Narration:
Next, we add a POST endpoint with optional cuisine and dietary, plus /health and /ready. Paste the Phase 2 prompt. Cline extends the backend and prints test commands.

Verification:
- Health: curl -s http://localhost:8010/health | jq
- Ready: curl -s http://localhost:8010/ready | jq
- POST: curl -s -X POST http://localhost:8010/api/v1/recipe -H "Content-Type: application/json" -d '{"cuisine":"Mexican","dietary":"vegan"}' | jq

Acceptance:
- Structured JSON response; both health endpoints OK.

On-screen:
- Paste Phase 2 prompt; approve changes; run tests.


06:25 - Phase 3 — Extract ingredients automatically (INGREDIENTS_LIST)
Narration:
We’ll enforce a structured output from the model. The app appends a final line beginning with INGREDIENTS_LIST: and we parse it into an array. Paste the Phase 3 prompt, approve the edit, and test.

On-screen:
- Show the parsed ingredients list in the JSON output.


06:55 - Phase 4 — Woolworths products with LLM reasoning
Narration:
Now an integration step. The service queries Woolworths for the top product candidates and attaches a brief reasoning string per item. We keep calls async with retries, timeouts, and concurrency guards. Paste Phase 4’s prompt, approve, then verify.

Verification:
curl -s "http://localhost:8010/api/v1/recipe?cuisine=Thai" | jq '.products // .woolworths_products | .[0:5]'

Acceptance:
- Products array populated with displayName, price, image, and reasoning.

On-screen:
- Show the products slice in the terminal.


07:40 - Phase 5 — Plotly Dash web app (local)
Narration:
Time for the UI. We’ll create a Plotly Dash app called Whats for Dinner? with filters, buttons for POST (Generate) and GET (Surprise me), clickable ingredient chips, product suggestions, and a Debug API Output panel.

Paste Phase 5’s prompt. Approve changes. Run the app:

python recipe-dash-app/app.py
# If 8050 is busy:
python recipe-dash-app/app.py --port 8051

If you’re on a VM, forward your port locally:
ssh -L 8051:localhost:8051 opc@OCI-Devops

Acceptance:
- UI loads, generates recipes, persists state, and shows raw JSON in Debug panel.

On-screen:
- Click Generate, toggle cuisine/dietary, show product suggestions.


08:35 - Phase 6 — Run FastAPI and Dash as systemd services
Narration:
For production readiness, we’ll run both services under systemd with restart policies and on-boot. Paste Phase 6’s prompt. This section is primarily informational; the guide lists the service management commands.

On-screen:
- Show the unit files and commands for status and logs.


09:00 - Phase 7 — Create a Local MCP Server for the Recipe API
Narration:
Local MCP servers let Cline call your domain tools directly — no app changes needed. We’ll stand up a small MCP server exposing get_recipe and post_recipe that call our API. Paste Phase 7’s prompt, provide the API base URL when asked, and register it.

Acceptance:
- From Cline, call the MCP tool to get an Italian pescatarian recipe and display the result.

On-screen:
- Cline calling MCP tool, result appears.


09:40 - Phase 8 — Optional advanced integrations (Containers, CI, API Gateway, Load Balancer)
Narration:
The guide includes containerization standards (run as non-root, port conventions, health checks), sample build and push commands to OCIR, and optional infrastructure steps for Container Instances, API Gateway, and Load Balancer. These are optional but show how the same Memory Bank and rules scale to infra.

On-screen:
- Highlight standards (non-root, health check endpoints, no secrets baked).
- Briefly show a sample docker build/push command filled via config.


10:20 - Phase 9 — End-to-end validation
Narration:
Finally, we run end-to-end checks: health and readiness, GET and POST recipes, UI headers, optional Container Instance health, API Gateway route test. If everything’s green, we’re done.

On-screen:
- Show the final checklist and green outputs in terminal.


10:45 - Cline workflow deep dive (Plan vs Act, tools, task_progress)
Narration:
You’ve seen the full loop:
- In Plan Mode, Cline explores and proposes a concrete plan with a todo checklist.
- In Act Mode, it executes one tool per step: edit a file, run a command, open a browser, use an MCP tool — and waits for confirmation after each step.
- It wraps with attempt_completion to summarize results.

Use task_progress in each step to keep a living contract of the work. This transparency is gold for teams and audits.

On-screen:
- Sample checklist being updated:
  - [x] Implement GET /recipe
  - [x] Add POST, health, readiness
  - [x] Parse INGREDIENTS_LIST
  - [x] Dash UI working
  - [x] Optional infra validated


11:25 - Best practices (replace vs write, standards, safety)
Narration:
- Prefer replace_in_file for targeted edits. Use write_to_file for new files or complete rewrites.
- Craft SEARCH blocks to match full lines exactly, respecting auto-formatting.
- Keep Memory Bank and .clinerules current; they’re your house rules.
- Keep temperature lower for code; add creativity only where it helps.
- One step, one tool; confirm each result.
- Never hardcode secrets or regions; use config files and resource principals.

On-screen:
- Quick compare: replace_in_file (scalpel) vs write_to_file (new canvas).


12:05 - Wrap-up + call to action
Narration:
We started with a question — whats for dinner? — and shipped a GenAI microservices app together by vibe coding with Cline and Oracle Code Assist. You saw how Memory Bank and .clinerules enforce consistency, how local MCP servers extend the assistant, and how Plan vs Act Mode keeps delivery reliable.

I’m Barjinder Singh, a Cloud Architect with Oracle in Sydney, Australia. Find more at fluffyclouds.blog. All links are below — try this in your repo, share your results, and subscribe for more end-to-end builds.

On-screen:
- Credits line with icons:
  Email: mail.barjinder@gmail.com
  Blog: fluffyclouds.blog
  LinkedIn: linkedin.com/in/barjinder-singh-48357555


Appendix - On-screen prompts you can pause and copy (from recipe-guide.html)

Phase 1 - FastAPI GET /recipe (key points)
- Build minimal FastAPI backend under recipe-api/
- Read Memory Bank and workshop-config.yaml
- Implement GET /recipe calling OCI GenAI endpoint
- Provide uvicorn command; use a virtual env

Verify:
curl -s "http://localhost:8010/api/v1/recipe" | jq


Phase 2 - POST, health, readiness
- Add POST /recipe (JSON body: optional cuisine, dietary)
- Add GET /health and GET /ready
- Return structured JSON; keep logging structured

Verify:
curl -s http://localhost:8010/health | jq
curl -s http://localhost:8010/ready | jq
curl -s -X POST http://localhost:8010/api/v1/recipe -H "Content-Type: application/json" -d '{"cuisine":"Mexican","dietary":"vegan"}' | jq


Phase 3 - INGREDIENTS_LIST
- Update prompt to append INGREDIENTS_LIST: ... at the end
- Parse into a simple list; include in API response


Phase 4 - Woolworths integration with reasoning
- Use GET /ui/Search/products with browser-like headers
- Return top-2 candidates; prefer LargeImageFile
- Async calls with concurrency guard, retries/backoff, timeouts
- Provide brief LLM reasoning with fallback

Verify (slice products):
curl -s "http://localhost:8010/api/v1/recipe?cuisine=Thai" | jq '.products // .woolworths_products | .[0:5]'


Phase 5 - Dash UI
- Build Plotly Dash app under recipe-dash-app/
- Filters, Generate (POST), Surprise me (GET)
- Ingredient chips, product suggestions with prices and reasons
- Test API button and Debug API Output panel
- Command to run (with backup port)

Run:
python recipe-dash-app/app.py
python recipe-dash-app/app.py --port 8051  # If needed


Phase 6 - systemd services
- Run FastAPI (uvicorn) and Dash with Restart=always, WantedBy=multi-user.target
- Use WorkingDirectory, prefer Python venv if present
- Show how to enable, start, and check logs


Phase 7 - Local MCP server
- Ask for API Base URL and register tools:
  - get_recipe: GET /recipe with optional cuisine, dietary
  - post_recipe: POST /recipe with optional cuisine, dietary
- Test by generating an Italian pescatarian recipe


Phase 8 - Optional containers/infra
- Containerize API and Dash (non-root uid 1000, health checks, ports)
- Build and push to OCIR
- Optional: Container Instance, API Gateway, Load Balancer (config-driven)


Phase 9 - End-to-end validation
- Health/readiness, GET/POST, UI reachable, optional MCP/CI/Gateway checks


Director notes (for pacing)
- Keep keyboard and terminal shots tight; zoom to results quickly.
- Use the checklist and section headers from the guide as chapter markers.
- If something fails, show Cline’s recovery loop: read errors, adjust, reapply, verify.
- Close with the credits footer and links (email, blog, LinkedIn).
