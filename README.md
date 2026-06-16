**This repo is supposed to be used as config by NvChad users!**

- The main nvchad repo (NvChad/NvChad) is used as a plugin by this repo.
- So you just import its modules , like `require "nvchad.options" , require "nvchad.mappings"`
- So you can delete the .git from this repo ( when you clone it locally ) or fork it :)

# Credits

1) Lazyvim starter https://github.com/LazyVim/starter as nvchad's starter was inspired by Lazyvim's . It made a lot of things easier!

# 🤖 Ecosistema de Inteligencia Artificial

Este entorno de Neovim está configurado con un Router de Inteligencia Artificial Dinámico, que permite escribir y refactorizar código en vivo. El sistema utiliza **claves de API estáticas (API Keys)** cargadas de forma efímera en memoria a través de un archivo `.env` que se mantiene ignorado por Git.

## 🔐 ¿Cómo obtener las API Keys?

### Proveedores Implementados:
Estas IAs están conectadas al sistema de enrutamiento y fallback. Si una agota sus tokens, el sistema detecta la falla y salta a la siguiente opción disponible automáticamente.

1. **Anthropic (Claude)**
   - **Link:** [Console Anthropic](https://console.anthropic.com/settings/keys)
   - **Instrucciones:** Crea una cuenta, ve al menú de API Keys, presiona "Create Key" y cópiala a tu `.env` como `ANTHROPIC_API_KEY`.

2. **OpenAI (ChatGPT)**
   - **Link:** [OpenAI API Keys](https://platform.openai.com/api-keys)
   - **Instrucciones:** Inicia sesión, dirígete al dashboard, genera una "New secret key" y guárdala como `OPENAI_API_KEY`.

3. **Google (Gemini Pro)**
   - **Link:** [Google AI Studio](https://aistudio.google.com/app/apikey)
   - **Instrucciones:** Entra con tu cuenta de Google, haz clic en "Create API key". Ofrece una de las capas gratuitas más grandes disponibles actualmente. Nómbrala `GEMINI_API_KEY`.

4. **Ollama (Modelos Locales - Fallback de emergencia)**
   - **Link:** [Descargar Ollama](https://ollama.com/)
   - **Instrucciones:** Instala Ollama en tu máquina. Luego corre en tu terminal local un comando como `ollama run llama3`. El router de Neovim usará subprocesos para detectar automáticamente todos los modelos que tengas instalados. ¡No necesita API Key y funciona sin internet!

---

### ⏳ Proveedores Faltantes (Siguientes Pasos):
Los siguientes motores son compatibles con la arquitectura actual, pero requieren extender las funciones de `credentials.lua` y `metrics.lua` para unirse al fallback:

- **DeepSeek:** Excelente relación costo/calidad en razonamiento de código.
- **Groq:** Para inferencia de modelos open-source en la nube a velocidades vertiginosas (LPU).
- **Mistral API:** Los modelos europeos (Mixtral/Mistral Large) como una sólida alternativa de alto rendimiento.
- **Cohere:** Excelentes modelos centrados en enterprise y bases de conocimiento.
