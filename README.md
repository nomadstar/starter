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

El Orquestador es la joya de la corona de este entorno. Es un flujo de trabajo maestro-esclavo asíncrono y ultra-avanzado donde tú actúas como el Director.

1. **Inyección de Contexto (Recursivo) y Web:** Al pedir la tarea, puedes inyectar archivos o carpetas enteras escribiendo `@ruta/al/archivo/`. Si pasas una carpeta, el orquestador leerá todos los archivos recursivamente (ignorando basura como `.git`, `node_modules`, `target` e imágenes automáticamente). También puedes pegar URLs (ej. `https://docs.rs/serde`) y descargará la web en Markdown limpio.
2. **Arquitectura y Modos Especiales:** El **Arquitecto Cloud** diseña el plan técnico y divide el trabajo en archivos (Chunks) pidiéndote *Feedback*. Posee modos inteligentes:
   - **`MODE: PLAN`**: Tareas complejas y de código fuente.
   - **`MODE: FAST`**: Tareas triviales (< 50 líneas) directas a código.
   - **`MODE: DOCS`**: (Exclusivo si el usuario lo pide). Desactiva el *Modo Cavernícola* y obliga a escribir enciclopedias y documentación exhaustiva sin resúmenes.
3. **Control Remoto Vía Telegram:** Monitorea y dirige todo el escuadrón desde tu teléfono móvil. El sistema envía logs en vivo por Telegram y hace *Long Polling*. Puedes aprobar planes escribiendo `/approve` en Telegram, dar feedback de correcciones, o detener una IA rebelde escribiendo `/kill` 😈.
4. **Contexto Infinito (Continuación Recursiva):** Se acabaron los "archivos cortados por la mitad". Si Ollama se queda sin tokens de salida, el orquestador concatena lo generado, reinyecta el prompt pidiendo que continúe exactamente donde se quedó, y repite este ciclo en bucle invisible hasta que termina capítulos gigantes.
5. **Arquitectura Swarm (Relevos de Modelos Locales):** Si defines una lista separada por comas en `AGENT_LOCAL_MODEL` (ej: `llama3,qwen2.5-coder:14b`), el orquestador encadenará a los modelos locales. El primero crea un borrador y lo firma (`# Esto lo hizo llama3`), y el siguiente lo refina y lo mejora. Un trabajo de equipo en cascada totalmente autónomo.
6. **Autoevaluación (Defiende tu Código), Cooperación y Triage JSON:** La cadena de código generada se envía al Arquitecto de la Nube para defender su trabajo. El Arquitecto no solo evalúa el código final (Score 0-100), sino que devuelve métricas de **Cooperación** y puntajes individuales para cada modelo participante.
   - **Score >= 90:** Aprobado directamente.
   - **Score 80-89:** Error menor. El Arquitecto de la nube lo parchea quirúrgicamente.
   - **Score < 80:** Error grave. Se fuerza a Ollama a reescribir. **Liderazgo Dinámico:** El modelo local que obtuvo el mayor puntaje de cooperación es designado como "Líder" exclusivo para parchear el problema en la siguiente iteración.
7. **Director Humano (Human-in-the-Loop):** Incluso si el Arquitecto Cloud aprueba el archivo, el sistema se pausa y te pregunta a ti. Puedes aprobarlo (Enter) o rechazarlo enviando tu propio feedback para obligar a los modelos locales a dar otra iteración. ¡Tú tienes la última palabra en cada archivo!
8. **Kill Switch Global (Botón de Pánico):** Si las IA alucinan o quieres abortar inmediatamente, puedes ejecutar el comando `:AiRouterKill` en Neovim o enviar `/kill` por Telegram en *cualquier momento* (incluso mientras el código se está generando). Esto cortará de tajo las conexiones de red y apagará el enjambre.
9. **Despliegue Nativo Incremental:** Cada vez que un chunk es aprobado, se crea y guarda inmediatamente de forma nativa en tu disco duro (con Lua puro). ¡No tienes que esperar a que todo el proyecto termine para ver los resultados!
10. **Memoria y Aislamiento:** El Arquitecto posee una "memoria a corto plazo" inyectada automáticamente que le recuerda qué archivos ya fueron construidos y aprobados, evitando repetición y pérdida de contexto.
11. **Código Base 100% Modular:** Todo este motor (ubicado en `lua/plugins/ai_router/`) está segregado en módulos limpios: `api.lua` (Red), `ui.lua` (Buffers y Alertas), `relay.lua` (Motor Swarm), `utils.lua` (Helpers) y `orchestrator.lua` (Entrypoint principal). Esto permite extender funcionalidades sin romper el frágil ciclo asíncrono.

## ⌨️ Comandos y Atajos (Keymaps)

Una vez configurado tu `.env`, puedes invocar al sistema con los siguientes atajos:

| Atajo | Comando | Descripción |
|---|---|---|
| `<leader>ac` | **Chat AI (Routed)** | Abre un panel interactivo con la mejor IA disponible según tu `.env`. (Si `MODE=3`, esto lanza el Orquestador Multi-Agente). |
| `<leader>ai` | **Inline AI** | Escribe un prompt directamente sobre el código seleccionado para refactorizar en la misma línea. |
| `<leader>am` | **Multi-Agent (Manual)** | Abre la interfaz de colaboración donde un Arquitecto (Cloud) diseña minimizado y el Desarrollador (Ollama) escribe el código. Se revisan mutuamente (Max 3 veces). |
| `<leader>af` | **Report Failure** | Si ves que la API actual te da errores 429 (Límite alcanzado), pulsa este atajo para obligar al sistema a "saltar" permanentemente a la siguiente IA de tu lista de Fallback. |
| `:AiRouterKill` | **Kill Switch** | (Comando de Neovim) Aborta inmediatamente la generación asíncrona de los agentes y apaga el orquestador. |

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
