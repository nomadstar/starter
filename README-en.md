**This repo is supposed to be used as config by NvChad users!**

[🇪🇸 Ver versión en Español](README.md)

- The main nvchad repo (NvChad/NvChad) is used as a plugin by this repo.
- So you just import its modules , like `require "nvchad.options" , require "nvchad.mappings"`
- So you can delete the .git from this repo ( when you clone it locally ) or fork it :)

# Credits

1) Lazyvim starter https://github.com/LazyVim/starter as nvchad's starter was inspired by Lazyvim's . It made a lot of things easier!

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

### Operation Modes (`AI_ROUTER_MODE`)
You can change the editor's global behavior by modifying this variable:
- `1` **(Full Cloud):** Exclusively uses paid Cloud AIs. Disables Ollama.
- `2` **(Full Local):** 100% private and free system. Routes all traffic directly to your local Ollama binary.
- `3` **(Iterative AI):** Activates the **Multi-Agent Orchestrator**. (When using the chat shortcut, Neovim will make the Cloud and Ollama talk to each other iteratively to solve the problem).
- `4` **(Smart Fallback - Default):** Evaluates an estimate of your tokens and launches requests in a cascading fallback: `Anthropic -> OpenAI -> Gemini -> OpenRouter -> Together -> Ollama`.

### Caveman Mode (`CAVEMAN_MODE="true"`)
Based on the principle of *"why waste time say lot word when few word do trick"*. When activated, the Router injects deep instructions that forbid the AI from using greetings, long explanations, or complex grammar. It will deliver telegraphic language and raw code, drastically reducing your token costs by up to 75%.

## ⌨️ Commands and Keymaps

Once your `.env` is configured, you can invoke the system with the following keymaps:

| Keymap | Command | Description |
|---|---|---|
| `<leader>ac` | **Chat AI (Routed)** | Opens an interactive panel with the best AI available according to your `.env`. (If `MODE=3`, this launches the Multi-Agent Orchestrator). |
| `<leader>ai` | **Inline AI** | Write a prompt directly over the selected code to refactor it in-line. |
| `<leader>am` | **Multi-Agent (Manual)** | Opens the collaboration interface where an Architect (Cloud) creates a minimized design and the Developer (Ollama) writes the code. They review each other (Max 3 times). |
| `<leader>af` | **Report Failure** | If you see the current API returning 429 errors (Limit Reached), press this to force the system to permanently "jump" to the next AI in your Fallback list. |

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
