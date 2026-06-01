import cardioGemma4 from 'libcardio_gemma4.so';
import { ModelConfig } from './Types';

interface NativeGemma4Module {
  isBackendAvailable(): boolean;
  infer(prompt: string, modelPath: string, mmprojPath: string, maxTokens: number, temperature: number): string;
}

export interface Gemma4Response {
  text: string;
  status: string;
  error: string;
}

export class Gemma4Bridge {
  static infer(prompt: string, config: ModelConfig): Gemma4Response {
    if (!config.enableGemma4) {
      return {
        text: '',
        status: 'Rule fallback active; Gemma4 4B disabled in settings',
        error: ''
      };
    }

    const nativeModule = cardioGemma4 as NativeGemma4Module;
    try {
      if (!nativeModule.isBackendAvailable()) {
        return {
          text: '',
          status: 'Rule fallback active; HarmonyOS native Gemma4 backend is not installed',
          error: 'native backend unavailable'
        };
      }
      const text = nativeModule.infer(
        prompt,
        config.modelPath,
        config.mmprojPath,
        config.maxTokens,
        config.temperature
      );
      if (text.trim().length === 0) {
        return {
          text: '',
          status: 'Rule fallback active; Gemma4 4B returned empty text',
          error: 'empty model output'
        };
      }
      return {
        text,
        status: `Gemma4 4B offline native backend: ${config.nativeBackendName}`,
        error: ''
      };
    } catch (error) {
      return {
        text: '',
        status: 'Rule fallback active; Gemma4 4B native call failed',
        error: JSON.stringify(error)
      };
    }
  }
}
