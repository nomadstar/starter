**This repo is supposed to be used as config by NvChad users!**

[🇪🇸 Ver versión en Español](README.md)

- The main nvchad repo (NvChad/NvChad) is used as a plugin by this repo.
- So you just import its modules , like `require "nvchad.options" , require "nvchad.mappings"`
- So you can delete the .git from this repo ( when you clone it locally ) or fork it :)

# Credits

1) Lazyvim starter https://github.com/LazyVim/starter as nvchad's starter was inspired by Lazyvim's . It made a lot of things easier!

---

🎊🎉🐶🐶🐶 **NEW NATIVE OLLAMA SWARM MODE INTEGRATION!** 🐶🐶🐶🎉🎊
Our AiRouter Orchestrator now intelligently delegates to the new native `ollama swarm`! Your local agents will fly! 🐕🥳🚀

---

## 🚀 Installation

This repository acts as a full **NvChad**-based configuration. To install it on your machine, open your terminal and run:

```bash
# 1. Backup or clean previous Neovim installations
mv ~/.config/nvim ~/.config/nvim.bak
rm -rf ~/.local/share/nvim ~/.local/state/nvim

# 2. Clone this repository as your main Neovim configuration
git clone <YOUR_REPOSITORY_URL> ~/.config/nvim

# 3. Open Neovim. Lazy.nvim will automatically download NvChad and all AI plugins
nvim

# 4. Generate your AI environment file
cp ~/.config/nvim/.env.example ~/.config/nvim/.env
```
*(Don't forget to edit the `~/.config/nvim/.env` file to add your API Keys or configure your local Ollama path).*

---

# 🤖 AI Ecosystem Manual

This Neovim environment is equipped with a modular, iterative, and entirely provider-agnostic Artificial Intelligence system. Instead of being tied to a single service (like Copilot), this system acts as a **Dynamic Router** that automatically selects the best available AI based on your credits, speed, or your chosen operation mode.

## 🧠 Architecture and Plugins

The ecosystem is built upon two main components:
1. **[CodeCompanion.nvim]**: The base plugin that provides us with the chat interface (UI) and standard adapters to talk with different models.
2. **[AI Router (Custom)]**: Our private architecture (located at `lua/plugins/ai_router/`) that acts as a "Middleware". It analyzes metrics, injects security keys ephemerally, handles *fallback* when APIs go down, and implements the Multi-Agent Orchestrator.

## ⚙️ Configuration and Global Modes (`.env`)

All security and system behavior are controlled by a single file called **`.env`** at the root of your `nvim` folder. This file is **never pushed to GitHub** for security reasons (`.gitignore`). Copy the `.env.example` template and rename it to `.env` to get started.

### Main `.env` Variables

- **Credentials:** `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`, `TOGETHER_API_KEY`.
- **Local Paths:** `OLLAMA_CMD` (Points to your custom Turboquant binary) and `OLLAMA_HOST`.
- **Orchestrator:** `AGENT_MAX_ITERATIONS` (Correction attempts), `AGENT_NOISY_MODE` (Attention beep), `AGENT_CLOUD_MODEL`, `AGENT_LOCAL_MODEL`.

### Operation Modes (`AI_ROUTER_MODE`)
You can change the editor's global behavior by modifying this variable:
- `1` **(Full Cloud):** Exclusively uses paid Cloud AIs. Disables Ollama.
- `2` **(Full Local):** 100% private and free system. Routes all traffic directly to your local Ollama binary.
- `3` **(Iterative AI):** Activates the **Multi-Agent Orchestrator**. (When using the chat shortcut, Neovim will make the Cloud and Ollama talk to each other iteratively to solve the problem).
- `4` **(Smart Fallback - Default):** Evaluates an estimate of your tokens and launches requests in a cascading fallback: `Anthropic -> OpenAI -> Gemini -> OpenRouter -> Together -> Ollama`.

### Caveman Mode (`CAVEMAN_MODE="true"`)
Based on the principle of *"why waste time say lot word when few word do trick"*. When activated, the Router injects deep instructions that forbid the AI from using greetings, long explanations, or complex grammar. It will deliver telegraphic language and raw code, drastically reducing your token costs by up to 75%.

## 🤖 Multi-Agent Orchestrator (Mode 3 / `<leader>am`)

The Orchestrator is the crown jewel of this environment. It's a fully asynchronous, highly-advanced master-slave workflow where you act as the Director.

1. **Recursive Context Injection & Web:** When prompted for a task, you can inject entire files or folders by typing `@path/to/file/`. If you pass a folder, the orchestrator will recursively read all files inside (automatically ignoring garbage like `.git`, `node_modules`, `target`, and images). You can also paste URLs (e.g. `https://docs.rs/serde`), and the system will fetch the website as clean Markdown.
2. **Architecture & Special Modes:** The **Cloud Architect** evaluates the task complexity and designs a technical plan breaking the work into individual files (Chunks), asking for your interactive *Feedback*. It features intelligent modes:
   - **`MODE: PLAN`**: Complex logic and source code generation.
   - **`MODE: FAST`**: Trivial tasks (< 50 lines) straight to code.
   - **`MODE: DOCS`**: (Exclusive on explicit user request). Disables *Caveman Mode* and forces the generation of highly exhaustive encyclopedias and documentation without summarization.
3. **Telegram Remote Control:** Monitor and command your AI squadron right from your smartphone. The system broadcasts live logs via Telegram and performs *Long Polling*. You can approve plans by sending `/approve`, download generated files directly to the chat with `/cat <path>` or `/get <path>`, or stop a rogue AI by sending `/kill` 😈. Use the Neovim command `:NewTeleBot` to automatically load all these shortcuts into your bot's quick menu.
4. **Infinite Context (Recursive Continuation):** Say goodbye to "truncated files". If Ollama runs out of output tokens, the orchestrator concatenates the generated text, silently re-prompts the model to "continue exactly where it left off", and loops this process invisibly until massive chapters are completed.
5. **Swarm Architecture (Local Models Relay):** If you define a comma-separated list in `AGENT_LOCAL_MODEL` (e.g. `llama3,qwen2.5-coder:14b`), the orchestrator will chain the local models. The first one creates a draft and signs it (`# Esto lo hizo llama3`), and the next one refines and improves it. A fully autonomous cascading teamwork.
6. **Self-Review (Defend Your Code), Cooperation & JSON Triage:** The generated code chain is sent to the Cloud Architect to defend their work. The Architect not only evaluates the final code (Score 0-100), but also returns **Cooperation** metrics and individual scores for each participating model.
   - **Score >= 90:** Directly approved.
   - **Score 80-89:** Minor error. The Cloud Architect surgically patches the code on the fly.
   - **Score < 80:** Major error. Ollama is forced to rewrite. **Dynamic Leadership & Mentorship:** The worst-performing model attempts to redeem itself as an *Apprentice* (receiving a `mentorship_advice` in its prompt to improve), while the best model takes over as its reviewing *Master*. This prevents the swarm from converging onto a single dominant model. Additionally, the *Short-Circuit* algorithm will silently and automatically mute any hallucinations if a model goes rogue or outputs Markdown without valid commands, stopping the problem at its roots without throwing false network errors.
7. **Human-in-the-Loop Director:** Even if the Cloud Architect approves a file, the system pauses and asks you for the final verdict. You can approve it (Enter) or reject it by sending your own feedback to force the local models into another iteration. You always have the final say on every file!
8. **Global Kill Switch (Panic Button):** If the AI hallucinates or you want to abort immediately, you can execute the `:AiRouterKill` command in Neovim or send `/kill` via Telegram at *any time* (even while code is generating). This will instantly sever network connections and kill the swarm.
9. **Incremental Native Deployment:** Every time a chunk is approved, it is immediately written and saved natively to your hard drive (using pure Lua). You don't have to wait for the entire project to finish to see the results!
10. **Persistent Memory and Isolation:** The Architect has an automatically injected short-term and long-term memory (`.ai_router_state.md`) that reminds it of the original directive and which files have already been built. The Architect never forgets its original purpose regardless of how many hours it has been working!
11. **Anti-Hibernation (Sleep Lock):** While the Orchestrator is running, Neovim uses `systemd-inhibit` to prevent your OS from sleeping, suspending, or hibernating. This prevents hours-long processes from dying in the middle of the night. *This lock is temporary, harmless, and releases automatically as soon as the Orchestrator finishes or you kill it.*
12. **100% Modular Codebase:** This entire engine (located in `lua/plugins/ai_router/`) is segregated into clean modules: `api.lua` (Network), `ui.lua` (Buffers and Alerts), `relay.lua` (Swarm Engine), `utils.lua` (Helpers), and `orchestrator.lua` (Main Entrypoint). This allows extending functionality without breaking the fragile asynchronous cycle.
13. **MidnightMonster Mode (Autonomous Night Delegation):** Between 10:00 PM and 8:00 AM, if you enable `MIDNIGHT_MONSTER="true"` in your `.env`, the system will stop asking for human approval to proceed. Instead, the Cloud Architect will evaluate the code from the local Ollamas or their suggestions for new files to determine if they meet the goal. If approved, the system moves forward automatically. The human can go to sleep while the local engine and cloud validation work together all night! The Telegram `/kill` and `/q` commands still work if you need to intervene.

## ⌨️ Commands and Keymaps

Once your `.env` is configured, you can invoke the system with the following keymaps:

| Keymap | Command | Description |
|---|---|---|
| `<leader>ac` | **Chat AI (Routed)** | Opens an interactive panel with the best AI available according to your `.env`. (If `MODE=3`, this launches the Multi-Agent Orchestrator). |
| `<leader>ai` | **Inline AI** | Write a prompt directly over the selected code to refactor it in-line. |
| `<leader>am` | **Multi-Agent (Manual)** | Opens the collaboration interface where an Architect (Cloud) creates a minimized design and the Developer (Ollama) writes the code. They review each other (Max 3 times). |
| `<leader>af` | **Report Failure** | If you see the current API returning 429 errors (Limit Reached), press this to force the system to permanently "jump" to the next AI in your Fallback list. |
| `:AiRouterToggle` | **Toggle UI** | (Neovim Command or press `q`) Hides the Orchestrator window to the background without killing the process. Run it again to summon the window back. |
| `:AiRouterKill` | **Kill Switch** | (Neovim Command) Instantly aborts the asynchronous generation of the agents and kills the orchestrator. |

---

## 🔐 How to get API Keys?

Here are the direct links to securely get your credentials.

1. **Anthropic (Claude)**
   - **Link:** [Anthropic Console](https://console.anthropic.com/settings/keys)
   - **Instructions:** Create an account, go to API Keys, press "Create Key", and save it as `ANTHROPIC_API_KEY`.

2. **OpenAI (ChatGPT)**
   - **Link:** [OpenAI API Keys](https://platform.openai.com/api-keys)
   - **Instructions:** Generate a "New secret key" and save it as `OPENAI_API_KEY`.

3. **Google (Gemini Pro)**
   - **Link:** [Google AI Studio](https://aistudio.google.com/app/apikey)
   - **Instructions:** One of the largest free tiers available. Name it `GEMINI_API_KEY`.

4. **Universal Aggregators (Hundreds of models in a single key)**
   - Access thousands of Open Source and closed models by paying per use or using free tiers.
   - **OpenRouter:** [Keys here](https://openrouter.ai/keys) (`OPENROUTER_API_KEY`).
   - **Together AI:** [Keys here](https://api.together.xyz/settings/api-keys) (`TOGETHER_API_KEY`).

5. **Ollama (Local Models - Private)**
   - **Instructions:** Doesn't require an API Key. The router will connect to your Ollama binary (configured in `OLLAMA_CMD`) locating all models asynchronously.

---

### ⏳ Next Steps and Alternatives:
Most of the world's models are already covered under the **OpenRouter** and **Together AI** aggregators. However, if you wish to add direct hardware connections in the future:
- **Direct Mistral API**
- **Cohere API**
