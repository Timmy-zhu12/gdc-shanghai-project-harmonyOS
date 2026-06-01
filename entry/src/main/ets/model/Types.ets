export const SUPPORTED_EXTENSIONS: string[] = [
  '.png',
  '.jpg',
  '.jpeg',
  '.bmp',
  '.tif',
  '.tiff',
  '.dcm',
  '.dicom',
  '.dcom'
];

export const DICOM_EXTENSIONS: string[] = [
  '.dcm',
  '.dicom',
  '.dcom'
];

export interface RawFile {
  uri: string;
  name: string;
  extension: string;
  bytes: Uint8Array;
}

export interface LoadedImage {
  uri: string;
  name: string;
  frameIndex: number;
  width: number;
  height: number;
  rgb: Uint8Array;
  sourceType: string;
  metadata: Record<string, string>;
}

export interface FrameAnalysis {
  loaded: LoadedImage;
  view: string;
  phase: string;
  chamberAreaProxy: number;
  hasColorDoppler: boolean;
  bmodeFeatures: number[];
  flowFeatures: number[];
  notes: string;
}

export interface StudyAnalysis {
  frames: FrameAnalysis[];
  viewCount: number;
  inputCount: number;
  systoleCount: number;
  diastoleCount: number;
  meanBmode: number[];
  meanFlow: number[];
  contractilityProxy: number;
  coverageWarning: string;
  featureSummary: string;
}

export interface TeachingJudgment {
  label: string;
  confidence: string;
  rationale: string;
}

export interface ModelConfig {
  enableGemma4: boolean;
  nativeBackendName: string;
  modelPath: string;
  mmprojPath: string;
  maxTokens: number;
  temperature: number;
}

export interface DiagnosisResult {
  report: string;
  status: string;
  prompt: string;
  judgment: TeachingJudgment;
}

export function emptyModelConfig(): ModelConfig {
  return {
    enableGemma4: false,
    nativeBackendName: 'cardio_gemma4_napi',
    modelPath: '/data/storage/el2/base/files/models/gemma-4-4b-it-Q4_K_M.gguf',
    mmprojPath: '/data/storage/el2/base/files/models/gemma-4-4b-mmproj-Q4_0.gguf',
    maxTokens: 640,
    temperature: 0.15
  };
}

export function compactFeatureText(study: StudyAnalysis): string {
  const bmode = study.meanBmode.map((value: number): string => value.toFixed(4)).join(', ');
  const flow = study.meanFlow.map((value: number): string => value.toFixed(4)).join(', ');
  return `views=${study.viewCount}, files_or_frames=${study.inputCount}, systole=${study.systoleCount}, diastole=${study.diastoleCount}, contractility_proxy=${study.contractilityProxy.toFixed(4)}\nB-mode mean features=[${bmode}]\nDoppler mean features=[${flow}]`;
}

export function fileExtension(name: string): string {
  const dot = name.lastIndexOf('.');
  if (dot < 0) {
    return '';
  }
  return name.substring(dot).toLowerCase();
}

export function fileStem(name: string): string {
  const slash = Math.max(name.lastIndexOf('/'), name.lastIndexOf('\\'));
  const base = slash >= 0 ? name.substring(slash + 1) : name;
  const dot = base.lastIndexOf('.');
  if (dot < 0) {
    return base;
  }
  return base.substring(0, dot);
}
