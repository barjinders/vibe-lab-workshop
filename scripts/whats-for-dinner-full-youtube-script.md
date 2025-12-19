Title: Build and Ship a GenAI Microservices App by Vibe Coding with Cline (What's for Dinner?)
Host: Barjinder Singh (Sydney, Australia) - Oracle Cloud Architect - fluffyclouds.blog

Target length: 15-20 minutes
Format: Teleprompter-ready narration + on-screen cues + demo steps


00:00 - Cold open (hook)
Narration (energetic, with a chuckle):
What if you could build and deploy a GenAI microservices app just by chatting about it? Today, I'm putting together 'What's for Dinner?' — this fun little concept app that tackles the age-old, existential question kids (and hangry adults like me) ask every night: "What's for dinner?" We'll vibe code the whole thing end-to-end using Cline with Oracle Code Assist, hook up some AI, throw in a Plotly Dash UI, and make sure it all works. No smoke and mirrors — just straightforward natural language, solid rules, and real production vibes.

On-screen:
- Quick montage: VS Code flying open, Cline chat popping, terminal commands running, browser showing a tasty recipe UI, checklist items checking off.
- Title card: Vibe Coding a GenAI Microservices App with Cline — Barjinder Singh (fluffyclouds.blog) — Sydney, Australia


00:25 - Host intro + credibility
Narration (friendly, like talking to a mate):
G'day everyone, I'm Barjinder Singh, based out of sunny Sydney, Australia. I'm a Cloud Architect at Oracle, and I share my thoughts on fluffyclouds.blog. In this video, I'll walk you through how I plan and launch a simple yet legit GenAI app using Cline powered by Oracle Code Assist. We'll lean on some key guardrails like Memory Bank, .clinerules, local MCP servers, and that strict Plan vs Act flow to keep things on track.

On-screen lower-third:
Barjinder Singh — Oracle Cloud Architect — Sydney, Australia
fluffyclouds.blog  |  linkedin.com/in/barjinder-singh-48357555


00:45 - What we're building (What's for Dinner?)
Narration:
So, 'What's for Dinner?' is this neat little GenAI microservices app that:
- Whips up dinner recipe ideas based on stuff like cuisine or dietary needs.
- Pulls out an ingredients list for easy shopping.
- Optionally grabs product suggestions from Woolworths, with a bit of smart reasoning.
- Serves it all up in a user-friendly Plotly Dash interface.
- Runs locally, as background services, or even containerized with API Gateway and Load Balancer for that full prod feel.

On-screen:
- Flash up the conceptual architecture from recipe-guide.html.
- Bullet list of phases (1 to 9) we'll hit from the guide.


01:20 - Quick primer on how Cline works
Narration:
Cline's basically your AI coding buddy that lives right in your setup. It can read and tweak files, fire off commands, spin up a browser for testing, and tap into external tools via Model Context Protocol. The cool part? It does one thing at a time, waits for your thumbs up after each step, and tweaks based on what you say.

Stuff we'll use today:
- Plan Mode: For scouting things out and nailing down a plan.
- Act Mode: Where the magic happens — editing files, running stuff, all step by step.
- Memory Bank vs .clinerules: One's for the big picture and context, the other's your strict rulebook.
- Local MCP servers: Easy way to plug in your own APIs.
- Model settings: Dial in the right AI provider and tweaks for solid results.

On-screen:
- Side-by-side: Plan Mode (thinking cap) vs Act Mode (getting hands dirty).
- Bullet: One tool per go, always check in with you.


02:00 - Setting up Cline with Oracle Code Assist
Narration:
We'll kick off with Oracle Code Assist as our Cline provider. Jump into Cline settings, pick Oracle Code Assist, log in with your Oracle account, and go for a solid model that's good for code and tools. I keep the temperature low for precise coding bits — bump it up a tad only when brainstorming.

Quick settings tips:
- Provider: Oracle Code Assist
- Default model: Something versatile for code and tools
- Temperature: 0.2-0.4 for code work
- Max steps per task: 15-25 to avoid endless loops
- Auto-approve: Only for safe reads, if at all
- Timeouts/retries: Set 'em for your setup and MCP calls

On-screen:
- Walk through Cline settings screen.
- Link in description: docs.cline.bot/introduction/welcome


02:40 - Memory Bank and .clinerules — the secret sauce
Narration:
Before Cline does anything, it checks two spots:
- Memory Bank: That's where I jot down what we're aiming for, why, and where we're at. Keeps everything aligned with the project vision.
- .clinerules: My non-negotiable rules — think API standards, logging dos and don'ts, container best practices, and how MCP stuff should behave.

You can even toss in an agent.md in Memory Bank to shape Cline's personality — like, "Stick to .clinerules no matter what, go for small edits, and keep that task checklist rolling."

On-screen:
- Quick tree view:
  memory-bank/
    agent.md, standards.md, progress.md
  .clinerules/
    10-devops-standards.md, 11-mcp-standards.md, 99-style.md


03:20 - Following along with recipe-guide.html
Narration:
I'm basing all this on recipe-guide.html — it's got the full nine-phase breakdown, copy-paste prompts for Cline, diagrams, test commands, and tips for going full prod.

Our plan:
0) Quick setup
1) FastAPI GET for recipes
2) Add POST, health checks
3) Pull out ingredients
4) Woolies products with smarts
5) Dash UI
6) Systemd services
7) Local MCP server
8) Extra: Containers, DevOps, Gateway, LB
9) Full test run

On-screen:
- Scroll the guide's table of contents, highlight phases.


03:55 - Phase 0: Getting set up
Narration:
First up, the one-off setup from the guide. Run the script to build out Memory Bank, .clinerules, and config file. Then tweak workshop-config.yaml with your details — no hardcoding secrets here, folks.

On-screen steps:
- Fire up setup_ws_dash.sh
- Edit workshop-config.yaml placeholders.
- Point out warnings and tips from the guide.


04:25 - Jumping into Cline workflow
Narration:
Here's my flow: Start in Plan Mode to scout and agree on steps. Switch to Act Mode for the real work — Cline suggests changes, I approve, it does one thing, shows results, repeat.

On-screen:
- Cline interface: Plan summary, then flip to Act.


04:45 - Phase 1: Basic FastAPI with GET /api/v1/recipe
Narration:
Let's build a simple FastAPI backend that spits out a random recipe, pulling from Memory Bank and config. Grab the Phase 1 prompt from the guide, paste into Cline. It'll set up the API, connect to GenAI, and give you a command to run it.

Test it:
curl -s "http://localhost:8010/api/v1/recipe" | jq

Good if:
- You get JSON with title, ingredients, steps.

On-screen:
- Paste prompt, approve, run uvicorn, curl it.


05:40 - Phase 2: POST, health, readiness
Narration:
Add POST with options, plus health/ready endpoints. Paste Phase 2 prompt, let Cline update, test away.

Tests:
- curl -s http://localhost:8010/health | jq
- curl -s http://localhost:8010/ready | jq
- curl -s -X POST ... with Mexican vegan params | jq

Good if:
- JSON looks right, health is green.

On-screen:
- Prompt, changes, tests.


06:25 - Phase 3: Auto-extract ingredients
Narration:
Force the model to output a structured ingredients list, parse it. Phase 3 prompt, update, check output.

On-screen:
- JSON with parsed list.


06:55 - Phase 4: Woolies products + reasoning
Narration:
Integrate Woolworths search, add reasoning for picks. Async, safe calls. Phase 4 prompt, verify.

Test:
curl ... | jq products slice

Good if:
- Products with names, prices, images, reasons.

On-screen:
- Terminal slice.


07:40 - Phase 5: Plotly Dash UI
Narration:
Now the front end — Dash app with filters, buttons, chips, suggestions, debug panel.

Phase 5 prompt, run:

python recipe-dash-app/app.py
Or with --port 8051 if needed.

Port forward if on VM.

Good if:
- UI works, generates, shows debug.

On-screen:
- Interact with UI.


08:35 - Phase 6: Systemd services
Narration:
Run 'em as services for reliability. Phase 6 prompt, guide has commands for setup.

On-screen:
- Unit files, status/logs commands.


09:00 - Phase 7: Local MCP server
Narration:
Set up MCP to call our API from Cline. Phase 7 prompt, input URL, test call.

Good if:
- Cline gets a recipe via MCP.

On-screen:
- Call and result.


09:40 - Phase 8: Optional prod stuff
Narration:
Containerize (non-root, health checks), push to OCIR, optional infra.

On-screen:
- Standards, sample commands.


10:20 - Phase 9: Full validation
Narration:
Check everything end-to-end.

On-screen:
- Green tests.


10:45 - Cline deep dive
Narration:
Saw the loop: Plan for strategy, Act for execution, task_progress for tracking.

On-screen:
- Updating checklist example.


11:25 - Tips
Narration:
Small edits preferred, match formatting, update banks/rules, low temp for code, confirm steps, no secrets.

On-screen:
- Replace vs write compare.


12:05 - Wrap
Narration:
From dinner question to shipped app with Cline. Check fluffyclouds.blog, links below, subscribe!

On-screen:
- Credits with contacts.


Appendix - Prompts from guide
[Same as before, trimmed for brevity]
