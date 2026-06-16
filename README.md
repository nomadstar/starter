**This repo is supposed to be used as config by NvChad users!**

[🇺🇸 View in English](README-en.md)

- The main nvchad repo (NvChad/NvChad) is used as a plugin by this repo.
- So you just import its modules , like `require "nvchad.options" , require "nvchad.mappings"`
- So you can delete the .git from this repo ( when you clone it locally ) or fork it :)

# Credits

1) Lazyvim starter https://github.com/LazyVim/starter as nvchad's starter was inspired by Lazyvim's . It made a lot of things easier!

---

## 🚀 Instalación

Este repositorio funciona como una configuración completa basada en **NvChad**. Para instalarlo en tu máquina, abre tu terminal y ejecuta:

```bash
# 1. Limpia instalaciones previas de Neovim (o hazles backup)
mv ~/.config/nvim ~/.config/nvim.bak
rm -rf ~/.local/share/nvim ~/.local/state/nvim

# 2. Clona este repositorio como tu configuración principal
git clone <URL_DE_TU_REPOSITORIO> ~/.config/nvim

# 3. Abre Neovim. Lazy.nvim instalará automáticamente NvChad y todos los plugins de IA
nvim

# 4. Genera tu archivo de entorno para la IA
cp ~/.config/nvim/.env.example ~/.config/nvim/.env
```
*(Edita el archivo `~/.config/nvim/.env` para añadir tus API Keys o configurar tu ruta de Ollama).*

---

# 🤖 Manual del Ecosistema de Inteligencia Artificial

Este entorno de Neovim está equipado con un sistema de Inteligencia Artificial modular, iterativo y completamente agnóstico al proveedor. En lugar de atarte a un solo servicio (como Copilot), este sistema actúa como un **Enrutador Dinámico** que selecciona automáticamente la mejor IA disponible según tus créditos, velocidad, o el modo de operación que elijas.

## 🧠 Arquitectura y Plugins

El ecosistema está construido en base a dos componentes principales:
1. **[CodeCompanion.nvim]**: El plugin base que nos provee de la interfaz de chat (UI) y adaptadores estándar para hablar con distintos modelos.
2. **[AI Router (Custom)]**: Nuestra arquitectura privada (ubicada en `lua/plugins/ai_router/`) que actúa como un "Middleware" o intermediario. Analiza las métricas, inyecta las llaves de seguridad de forma efímera, maneja el *fallback* cuando se caen las APIs, e implementa el Orquestador Multi-Agente.

## ⚙️ Configuración y Modos Globales (`.env`)

Toda la seguridad y comportamiento del sistema se controla mediante un único archivo llamado **`.env`** en la raíz de tu carpeta `nvim`. Este archivo **nunca se sube a GitHub** por seguridad (`.gitignore`). Copia la plantilla `.env.example` y renómbrala a `.env` para empezar.

### Variables Principales del `.env`

- **Credenciales:** `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`, `TOGETHER_API_KEY`.
- **Rutas Locales:** `OLLAMA_CMD` (Apunta a tu binario customizado con Turboquant) y `OLLAMA_HOST`.
- **Orquestador:** `AGENT_MAX_ITERATIONS` (Intentos de corrección), `AGENT_NOISY_MODE` (Beep de atención), `AGENT_CLOUD_MODEL`, `AGENT_LOCAL_MODEL`.

### Modos de Operación (`AI_ROUTER_MODE`)
Puedes cambiar el comportamiento global del editor modificando esta variable:
- `1` **(Full Cloud):** Usa exclusivamente Inteligencias Artificiales de pago en la Nube. Desactiva Ollama.
- `2` **(Full Local):** Sistema 100% privado y gratuito. Enruta todo tráfico a tu binario local de Ollama.
- `3` **(Iterative AI):** Activa el **Orquestador Multi-Agente**. (Al usar el atajo de chat, Neovim pondrá a la nube y a Ollama a charlar iterativamente para resolver el problema).
- `4` **(Fallback Inteligente - Por Defecto):** Evalúa un estimado de tus tokens y lanza peticiones en cascada: `Anthropic -> OpenAI -> Gemini -> OpenRouter -> Together -> Ollama`.

### Modo Cavernícola (`CAVEMAN_MODE="true"`)
Basado en el principio de *"por qué usar muchas palabras si pocas funcionan"*. Al activarlo, el Router inyecta órdenes profundas que prohíben a la IA usar saludos, explicaciones largas o gramática compleja. Entregará lenguaje telegráfico y código crudo, reduciendo drásticamente tus costos por tokens hasta un 75%.

## 🤖 Orquestador Multi-Agente (Modo 3 / `<leader>am`)

El Orquestador es la joya de la corona de este entorno. Es un flujo de trabajo maestro-esclavo completamente asíncrono donde tú actúas como el Director:

1. **Inyección de Contexto:** Cuando te pida la tarea, puedes inyectar archivos enteros escribiendo `@ruta/al/archivo` (ej: `Refactoriza @src/main.rs usando @MANIFESTO.md`).
2. **Chat de Diseño:** Primero, el **Arquitecto Cloud** generará un plan. El sistema se pausará y te pedirá *Feedback*. Puedes discutir iterativamente el plan con el Arquitecto hasta que estés satisfecho (dejando el cuadro de texto vacío para aprobar).
3. **Iteraciones Automáticas:** Una vez apruebes el plan, el **Desarrollador Local** (Ollama) escribirá el código. El Arquitecto lo revisará y le exigirá correcciones automáticamente (hasta el límite de `AGENT_MAX_ITERATIONS`).
4. **Despliegue Seguro:** Al finalizar, el Arquitecto generará un script Bash (`deploy_ai.sh`) para crear todas las carpetas y archivos físicos. Te mostrará el script en pantalla dividida y te pedirá confirmación antes de ejecutarlo.
5. **Modo Ruidoso (Noisy Mode):** Como este proceso es asíncrono, puedes activar `AGENT_NOISY_MODE="true"` en tu `.env`. Neovim emitirá un suave beep cada 5 segundos cuando el proceso se detenga y necesite tu confirmación, para que puedas alejarte de la computadora tranquilamente.

## ⌨️ Comandos y Atajos (Keymaps)

Una vez configurado tu `.env`, puedes invocar al sistema con los siguientes atajos:

| Atajo | Comando | Descripción |
|---|---|---|
| `<leader>ac` | **Chat AI (Routed)** | Abre un panel interactivo con la mejor IA disponible según tu `.env`. (Si `MODE=3`, esto lanza el Orquestador Multi-Agente). |
| `<leader>ai` | **Inline AI** | Escribe un prompt directamente sobre el código seleccionado para refactorizar en la misma línea. |
| `<leader>am` | **Multi-Agent (Manual)** | Abre la interfaz de colaboración donde un Arquitecto (Cloud) diseña minimizado y el Desarrollador (Ollama) escribe el código. Se revisan mutuamente (Max 3 veces). |
| `<leader>af` | **Report Failure** | Si ves que la API actual te da errores 429 (Límite alcanzado), pulsa este atajo para obligar al sistema a "saltar" permanentemente a la siguiente IA de tu lista de Fallback. |

---

## 🔐 ¿Cómo obtener las API Keys?

Aquí tienes los enlaces directos para conseguir tus credenciales seguras.

1. **Anthropic (Claude)**
   - **Link:** [Console Anthropic](https://console.anthropic.com/settings/keys)
   - **Instrucciones:** Crea una cuenta, ve a API Keys, presiona "Create Key" y guárdala como `ANTHROPIC_API_KEY`.

2. **OpenAI (ChatGPT)**
   - **Link:** [OpenAI API Keys](https://platform.openai.com/api-keys)
   - **Instrucciones:** Genera una "New secret key" y guárdala como `OPENAI_API_KEY`.

3. **Google (Gemini Pro)**
   - **Link:** [Google AI Studio](https://aistudio.google.com/app/apikey)
   - **Instrucciones:** Una de las capas gratuitas más grandes. Nómbrala `GEMINI_API_KEY`.

4. **Agregadores Universales (Cientos de modelos en una sola llave)**
   - Accede a miles de modelos Open Source y cerrados pagando por uso o gratis.
   - **OpenRouter:** [Llaves aquí](https://openrouter.ai/keys) (`OPENROUTER_API_KEY`).
   - **Together AI:** [Llaves aquí](https://api.together.xyz/settings/api-keys) (`TOGETHER_API_KEY`).

5. **Ollama (Modelos Locales - Privado)**
   - **Instrucciones:** No requiere API Key. El router conectará con tu binario de Ollama (configurado en `OLLAMA_CMD`) localizando todos los modelos de forma asíncrona.

---

### ⏳ Siguientes Pasos y Alternativas:
La mayoría de los modelos del mundo ya están cubiertos bajo los agregadores **OpenRouter** y **Together AI**. Sin embargo, si deseas añadir conexiones directas de hardware a futuro:
- **Mistral API Directa**
- **Cohere API**
