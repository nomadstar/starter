
return {
  {
    "nomnivore/ollama.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "Ollama", "OllamaModel", "OllamaServe", "OllamaServeStop" },
    keys = {
      { "<leader>oo", ":<c-u>lua require('ollama').prompt()<cr>", desc = "ollama prompt", mode = { "n", "v" } },
      { "<leader>oG", ":<c-u>lua require('ollama').prompt('Generate_Code')<cr>", desc = "ollama Generate Code", mode = { "n", "v" } },
    },
    opts = {
      models = {
        "codellama:latest",
        "codegeex4:latest",
        "llama3:latest",
        "qwen2:0.5b",
        "llama3:8b",
        "codegeex4:9b",
        "codellama:7b",
      },
    },
  },
}



