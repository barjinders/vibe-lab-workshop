# YouTube Script: “Cline Deep Dive — Plan vs Act, Memory Bank vs .clinerules, MCP servers, and Model Settings”

Estimated runtime: 12–15 minutes
Audience: Developers and DevOps engineers evaluating AI-assisted development

00:00 — Cold open (hook)
- On‑screen: Terminal + VS Code timelapse with file edits, a browser popping up, and a checklist updating.
- Narration:
  “What if your AI assistant could read your repo, follow your house rules, run commands, and make precise file edits—step by step, with your approval? This is Cline. Today I’ll show you how Cline works, how it keeps context, and why Memory Bank and .clinerules are game‑changers. We’ll cover Plan vs Act Mode, local MCP servers, and how to configure model settings so you get predictable, production‑ready outcomes.”

00:25 — What is Cline (high level)
- Lower‑third: “Cline = AI developer with tools + guardrails”
- Narration:
  “Cline is an AI developer that operates inside your environment. It can:
  - Read, search, and edit files with surgical precision.
  - Run commands in your terminal.
  - Launch a headless browser for web tasks.
  - Call external tools via MCP (Model Context Protocol).
  All of this happens in a tight loop: one tool per step, it waits for your confirmation, and then proceeds. That iteration creates reliability you can ship with.”

01:10 — How Cline uses context
- On‑screen: Show “environment_details” block (open tabs, file structure, OS), then a code search example.
- Narration:
  “Cline constantly orients to context: open tabs, your OS, the current working directory, detected CLI tools, even active terminals. It prefers structured exploration—listing files, regex searching, then reading specific files—before proposing changes. That’s how it avoids guesswork and stays deterministic.”

01:45 — Modes: Plan Mode vs Act Mode
- On‑screen split: “Plan Mode” vs “Act Mode”
- Narration:
  “Cline has two modes:
  - Plan Mode: Discussion and planning. It can read/search files and then present a concrete plan using plan_mode_respond. This is where you align on scope and create a todo checklist.
  - Act Mode: Execution. It uses tools to implement the plan—edit files, run commands, open a browser—one step at a time, waiting for your confirmation after each step. When done, it uses attempt_completion to summarize the result.
  Think of Plan Mode as the design review; Act Mode as the operation theatre.”

02:40 — Memory Bank vs .clinerules (the difference)
- Title card: “Memory Bank vs .clinerules”
- Narration:
  “These two concepts are the backbone of consistency.”

  “Memory Bank:
  - A project‑local folder (commonly memory-bank/) that explains what you’re building, why, active context, and current progress.
  - It’s where you encode product intent, terminology, API surfaces, and workflows.
  - Cline reads this first to align with your goals and vocabulary.”

  “.clinerules:
  - A hidden folder of enforced standards and non‑negotiable constraints.
  - It encodes house rules: API contracts, logging standards, container policies, deployment conventions, security boundaries, and MCP expectations.
  - Cline treats these rules as guardrails. If a proposed change violates them, it adjusts the approach rather than ignoring the rules.”

- On‑screen example snippet (house‑rules excerpt):
  ```
  .clinerules/
  ├─ 10-devops-standards.md  # CI/CD, tagging, non-root containers, ports, healthchecks
  ├─ 11-mcp-standards.md     # Required tool shapes, timeouts, error handling
  └─ 99-style.md             # Naming, imports, linting, logging structure
  ```

03:50 — What is agent.md (and where it fits)
- Narration:
  “agent.md is a lightweight convention file some teams place in memory-bank/ to define the assistant’s role, voice, and priorities for this repository. It can include:
  - Persona and constraints (e.g., ‘Be strict about .clinerules’)
  - Scope boundaries (what to do vs what to avoid)
  - Decision‑making preferences (e.g., prefer replace_in_file over full rewrites)
  - Review checklists per change”
- On‑screen example:
  ```
  memory-bank/agent.md
  ---
  role: “Senior Dev + Release Captain”
  priorities:
    - Enforce .clinerules without exception
    - Prefer targeted edits; avoid churn
    - Keep a running task checklist (task_progress)
  boundaries:
    - Never hardcode secrets or regions
    - Always wait for user confirmation after tool use
  ```

04:50 — task_progress checklists (why they matter)
- Narration:
  “Cline can maintain a live checklist using the task_progress parameter on each tool call. This creates a visible, evolving contract for the work:
  - Roadmap clarity
  - Progress tracking
  - Fast reviews
  - Zero scope drift”
- On‑screen quick example:
  ```
  - [x] Analyze requirements
  - [x] Draft plan
  - [ ] Implement edits
  - [ ] Verify in browser
  - [ ] Commit & push
  ```

05:30 — Local MCP Servers (extend Cline with your own tools)
- Title card: “MCP: Plug in your own tools”
- Narration:
  “MCP (Model Context Protocol) lets Cline call external tools you expose—locally or remotely. Create a small server that provides tools like get_forecast or post_recipe, then register it so Cline can call those tools like first‑class citizens. This is ideal for domain systems: billing, inventory, or your internal APIs.”
- On‑screen: High‑level steps
  1) Build an MCP server exposing tools (JSON shapes with clear input/output).
  2) Run it locally.
  3) Add it to Cline’s MCP configuration.
  4) Call tools from prompts; Cline uses use_mcp_tool under the hood.
- On‑screen example call:
  ```
  MCP Tool: get_recipe
  args: { "cuisine": "Italian", "dietary": "vegetarian" }
  ```

06:50 — Tooling discipline (why one tool per step matters)
- Narration:
  “Cline intentionally uses one tool per step. It prevents cascading failures and keeps the review loop tight. For file edits, it prefers replace_in_file for surgical changes and write_to_file for initial scaffolding or full rewrites. After each step, it waits for explicit confirmation before proceeding.”

07:30 — Replace vs Write: editing best practices
- Narration:
  “Use replace_in_file for targeted edits and small refactors—fewer side effects and safer diffs. Use write_to_file to create new files or when a full rewrite is warranted. And remember: replace_in_file search blocks must match full lines exactly—whitespace and auto‑formatting included.”

08:15 — Plan Mode workflow (in practice)
- Narration:
  “In Plan Mode, Cline will:
  - Explore: list files, search, and read key files.
  - Synthesize a plan: clear steps + acceptance criteria.
  - Ask for sign‑off using plan_mode_respond.
  Only after alignment do you switch to Act Mode.”

08:50 — Act Mode workflow (in practice)
- Narration:
  “In Act Mode, Cline:
  - Executes one tool at a time (edit files, run commands, open browser, use MCP tools).
  - Waits for your confirmation results after each tool.
  - Adapts to errors immediately.
  - Concludes with attempt_completion summarizing results and optional demo command.”

09:30 — Configuring Model Settings (providers, models, and knobs)
- Title card: “Model Settings”
- Narration:
  “Cline is provider‑agnostic. Configure it to match your environment and compliance needs.”
- On‑screen: Settings checklist
  - Providers: Choose your API provider (e.g., Oracle Code Assist, OpenAI, etc.).
  - Default model: Pick a balanced model for code + tool‑use (e.g., latest general model).
  - Temperature: Lower for deterministic infra/code; increase slightly for ideation.
  - Max tool steps per task: Prevent runaway action loops.
  - Auto‑approve scope: For safe read/search steps only, if you choose to enable it.
  - Timeouts and retries: Especially for MCP tools or network calls.
  - Sandboxing: Keep risky operations guarded; prefer explicit approval for installs/deletes.
- Narration:
  “Start conservative. Increase creativity and concurrency only after your standards and guardrails are stable.”

10:45 — Demo beats you can replicate
- Narration:
  “A minimal, repeatable demo flow:
  1) Plan Mode: Ask Cline to propose a refactor plan for a module—require a todo checklist and success criteria.
  2) Act Mode: Approve, then let it apply a small replace_in_file patch; confirm the tool result.
  3) Run a unit test command; approve logs as feedback.
  4) Use a local MCP tool (like get_recipe) to show how external capability plugs in.
  5) Conclude with attempt_completion and a clean git commit.”
- On‑screen: Before/After diff with a tiny patch.

11:45 — Common pitfalls and pro tips
- Narration:
  “Pitfalls:
  - Vague asks without files: Cline will explore, but clarity accelerates everything.
  - Overusing write_to_file: Prefer precise replace_in_file to reduce churn.
  - Ignoring auto‑formatting: Always craft SEARCH blocks against the latest saved file content.
  - Skipping confirmations: Always wait for tool results; never assume success.”

  “Pro tips:
  - Keep Memory Bank and .clinerules current—your outcomes will feel ‘pre‑trained’ on your org.
  - Use task_progress to keep stakeholders aligned.
  - Add MCP tools for any domain service you call twice.”

12:30 — Wrap up + CTA
- Narration:
  “Cline turns AI from ‘code suggester’ into a dependable teammate that plans, executes, and verifies. With Memory Bank and .clinerules, you get repeatable results aligned to your standards. Add MCP servers to plug in your world, and tune model settings to match your risk profile.
  Links are below—try it in your repo, and let me know what you build.”

Appendix — Quick reference snippets

A) Example .clinerules snippet
```
# 10-devops-standards.md
- Containers must run as non-root (uid 1000)
- API port defaults to 8000 unless configured
- Healthcheck endpoint /health required
- No secrets or ~/.oci baked into images
```

B) Example memory-bank outline
```
memory-bank/
├─ activeContext.md   # What we’re building and why
├─ standards.md       # Naming, logging, API surface
├─ progress.md        # Current phase and acceptance criteria
└─ agent.md           # Persona, boundaries, priorities
```

C) Example MCP tool contract (conceptual)
```
Tool: get_recipe
Input:
  cuisine: string (optional)
  dietary: string (optional)
Output:
  { recipe: string, model: string, ... }
Error handling:
  - Timeouts with retry/backoff
  - Structured error { code, message }
```

D) Replace vs Write mental model
- replace_in_file: “Scalpel” — surgical edits; must match full lines exactly.
- write_to_file: “New canvas” — bootstrap files or full rewrites when justified.

E) Model settings checklist (starter)
- Provider: Your org’s approved provider
- Model: General code+tool model
- Temp: 0.2–0.4 for code; up to 0.7 for ideation
- Max steps: 15–25 (project size dependent)
- Auto‑approve: Off or read‑only operations
- Timeouts: 30–90s for external calls
- Safety: Explicit approval for installs/deletes/network operations
