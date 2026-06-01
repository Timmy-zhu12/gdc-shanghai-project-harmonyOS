# Native Gemma4 4B backend integration

The ArkTS application already contains a native NAPI bridge named `libcardio_gemma4.so`:

```text
entry/src/main/ets/model/Gemma4Bridge.ets
entry/src/main/cpp/CMakeLists.txt
entry/src/main/cpp/napi_init.cpp
entry/src/main/cpp/types/libcardio_gemma4/Index.d.ts
```

The checked-in C++ module is a safe stub. It returns `false` from `isBackendAvailable()` so the app remains runnable and falls back to the deterministic local rule engine.

To enable actual offline Gemma4 4B inference on HarmonyOS hardware:

1. Build or vendor a HarmonyOS-compatible inference runtime, usually a llama.cpp-based or equivalent GGUF runtime compiled with the HarmonyOS NDK.
2. Replace `napi_init.cpp` with calls into that runtime.
3. Implement model loading from `modelPath` and optional `mmprojPath`.
4. Keep `infer(prompt, modelPath, mmprojPath, maxTokens, temperature)` returning a UTF-8 string.
5. Preserve the fallback behavior when the model file cannot be opened or memory is insufficient.

Expected model path used by the UI:

```text
/data/storage/el2/base/files/models/gemma-4-4b-it-Q4_K_M.gguf
/data/storage/el2/base/files/models/gemma-4-4b-mmproj-Q4_0.gguf
```

Large GGUF files are excluded from GitHub. Copy them to the device or package them through a private test build only when the competition rules and device storage allow it.
