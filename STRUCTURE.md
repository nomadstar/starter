# Estructura del Código: AI Router (Orquestador Multi-Agente)

Este documento describe la arquitectura interna del código del plugin `ai_router` alojado en `~/.config/nvim/lua/plugins/ai_router/`. 

La arquitectura fue refactorizada y modularizada para evitar un código "spaghetti", separando las responsabilidades de red, interfaz de usuario y lógica de agentes en archivos aislados. Si necesitas modificar el sistema o arreglar un bug, usa este documento como mapa.

---

## Árbol de Archivos

```text
lua/plugins/ai_router/
├── orchestrator.lua     # Entrypoint principal y controlador macro
├── api.lua              # Peticiones HTTP, JSON y comunicación con LLMs
├── relay.lua            # Motor Swarm (Lógica de relevos y auto-evaluación local)
├── ui.lua               # Interfaz gráfica (buffers, logs, pitidos)
├── utils.lua            # Funciones puras de ayuda, lectura de .env, file IO
├── telegram.lua         # Cliente de Long Polling para control remoto por Telegram
└── metrics.lua          # Sistema de recolección de tokens y estadísticas
```

---

## Detalles de cada Módulo

### 1. `orchestrator.lua` (Controlador Principal)
Es el punto de entrada cuando el usuario ejecuta `<leader>am`.
- **Responsabilidades:**
  - Desplegar la UI flotante.
  - Solicitar el prompt inicial al usuario.
  - Detectar y extraer URLs usando *Jina Reader*.
  - Comunicarse con el Arquitecto Cloud para generar un plan de ejecución (`execute_architecture`).
  - Gestionar el feedback interactivo (local o vía Telegram).
  - Iniciar el motor de relevos (`start_relay`).

### 2. `api.lua` (Capa de Red)
Aísla completamente el uso de la librería `plenary.curl`.
- **Responsabilidades:**
  - `call_cloud(prompt, callback)`: Maneja la comunicación con modelos en la nube (OpenRouter). Gestiona los reintentos (fallback) a otros modelos en la nube si hay errores HTTP 429/500, e inyecta llaves de API dinámicamente.
  - `call_ollama(model, prompt, callback)`: Maneja la comunicación local. Posee protección contra respuestas nulas (ej. timeout de red local) y maneja el bucle infinito de "Continuación" cuando Ollama se queda sin tokens (`data.done_reason == "length"`).

### 3. `relay.lua` (Motor Swarm)
Contiene la lógica de iteración recursiva y colaboración multi-modelo.
- **Responsabilidades:**
  - `process_chunk()`: Toma un archivo del plan del arquitecto y gestiona su ciclo de vida de generación.
  - `do_iteration()`: Inicia el bucle de "Relevo" donde cada modelo local toma el código, lo edita, firma su contribución (`# Esto lo hizo llama3`) y lo pasa al siguiente modelo de la cadena configurada en `AGENT_LOCAL_MODEL`.
  - `finish_relay()`: Activa el proceso de Defensa. Le pide al último modelo local que califique su trabajo y luego envía esta defensa al Arquitecto Cloud.
  - **Liderazgo Dinámico**: Si el Arquitecto rechaza el código (Score < 80), `relay.lua` analiza los `cooperation_scores`, extrae al modelo ganador, y le delega el liderazgo exclusivo para la próxima iteración.

### 4. `ui.lua` (Capa de Interfaz de Usuario)
Evita que la lógica del negocio se mezcle con APIs de la interfaz de Neovim (`vim.api`).
- **Responsabilidades:**
  - `create_floating_window()`: Instancia y configura el buffer de Markdown centrado.
  - `log(msg)`: Imprime texto asíncronamente en el buffer sin romper el hilo de Lua.
  - `start_attention_beeper()`: Maneja el timer que ejecuta `paplay` en bucle si `AGENT_NOISY_MODE` está activo.
  - `dump_state()`: Escribe el archivo local `.ai_router_state.md` con el estado en vivo de la memoria del orquestador.

### 5. `utils.lua` (Herramientas y Entorno)
Funciones auxiliares que no tienen estado (Stateless).
- **Responsabilidades:**
  - `get_env()` y `get_local_models()`: Interfaz segura para leer el archivo `.env`.
  - `save_file_native(filename, content)`: Lógica robusta que crea directorios recursivamente (`mkdir -p`) y guarda el código generado directamente en el disco.
  - `jina_fetch()`: Utilidad para raspar el contenido de páginas web y pasarlas a Markdown.

### 6. `telegram.lua` & `metrics.lua`
- `telegram.lua`: Un bucle infinito ligero (Long Polling) que consulta la API de Telegram, permite aprobar planes con `/approve` y mata el proceso con `/kill`.
- `metrics.lua`: Acumulador global que rastrea cuántos tokens se han consumido durante la sesión para estimar costos.

---

## Flujo de Ejecución Básico (Call Graph)

1. Usuario invoca `<leader>am`.
2. `orchestrator.start_orchestration()` -> Llama a `ui.create_floating_window()`.
3. Extrae URLs con `utils.jina_fetch()`.
4. Llama a `api.call_cloud()` para obtener el Plan del Arquitecto.
5. Inicia recursivamente `relay.process_chunk()`.
6. Dentro de `process_chunk()`, se inicia `do_iteration()`, que llama a `api.call_ollama()` múltiples veces en cascada (Swarm).
7. Al terminar la cascada, llama a `api.call_cloud()` para evaluación.
8. Si pasa la evaluación, `utils.save_file_native()` guarda en disco.
9. Se repite el paso 5 con el siguiente archivo del plan.
