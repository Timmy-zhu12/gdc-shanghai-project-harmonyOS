# Gemma4 4B model directory

Place local model files here only on the development machine or device package used for private testing.

Recommended names:

```text
gemma-4-4b-it-Q4_K_M.gguf
gemma-4-4b-mmproj-Q4_0.gguf
```

The repository intentionally ignores `.gguf`, `.bin`, and `.safetensors` files because they are large and should not be pushed to GitHub. For HarmonyOS devices, the preferred production path is a native NAPI backend backed by llama.cpp or an equivalent offline inference runtime. The ArkTS app keeps the same Gemma4 prompt contract and falls back to deterministic local rules if the native backend is not present.
