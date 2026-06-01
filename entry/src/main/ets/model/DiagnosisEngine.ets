import { DiagnosisResult, ModelConfig, StudyAnalysis, TeachingJudgment, compactFeatureText } from './Types';
import { Gemma4Bridge } from './Gemma4Bridge';

interface LowEfCalibrationEstimate {
  probability: number;
  threshold: number;
  positive: boolean;
  compactText: string;
}

const LOW_EF_MEANS: number[] = [
  0.3439935179, 0.1202890558, 0.0257984379, 0.0245626505,
  0.0402119582, 0.0737082141, 0.7069971181, 0.4954215066,
  0.1480851636, 0.0763964283, 0.0746771633, 1.3412349234,
  0.0336320823, 0.7312120198
];

const LOW_EF_SCALES: number[] = [
  0.0320823992, 0.0130243928, 0.0025158036, 0.0021835693,
  0.0035243618, 0.0154935366, 0.0205262283, 0.0097401574,
  0.0088450145, 0.0618941601, 0.0176097238, 0.1334816438,
  0.0174574480, 0.0417555305
];

const LOW_EF_COEFFS: number[] = [
  0.6227405327, -0.0138485092, 0.2119849661, -0.2368895083,
  0.1975460847, 0.0613060324, 0.7014784635, 1.4841314955,
  0.2065621561, 0.2448794316, 0.7444971896, 0.4895215522,
  -0.5426316802, 1.0054161135
];

const LOW_EF_INTERCEPT: number = 0.3068175790;
const LOW_EF_THRESHOLD: number = 0.270;

export class DiagnosisEngine {
  static runDiagnosis(study: StudyAnalysis, config: ModelConfig): DiagnosisResult {
    const prompt = DiagnosisEngine.buildGemma4Prompt(study);
    const bridge = Gemma4Bridge.infer(prompt, config);
    const judgment = DiagnosisEngine.classifyTeachingCondition(study);
    if (bridge.text.trim().length > 0) {
      return {
        report: bridge.text.trim(),
        status: bridge.status,
        prompt,
        judgment
      };
    }

    const fallback = DiagnosisEngine.heuristicDiagnosis(study, judgment);
    const suffix = bridge.error.length > 0 ? `\n\n[Gemma4 4B 调用未完成，已使用本地规则后备：${bridge.error}]` : '';
    return {
      report: `${fallback}${suffix}`,
      status: bridge.status,
      prompt,
      judgment
    };
  }

  static buildGemma4Prompt(study: StudyAnalysis): string {
    const judgment = DiagnosisEngine.classifyTeachingCondition(study);
    return `你是离线运行在华为 HarmonyOS 设备上的 Gemma4 4B 医学教学辅助工具。你正在分析脱敏心脏超声图像的本地边缘计算特征。
任务：必须给出一个明确的“教学参考病症判断”，病症名称要精确到具体超声常见病症，例如“轻度二尖瓣反流”“轻度三尖瓣反流”“主动脉瓣轻度狭窄倾向”“左心室收缩功能减低”等，不要只说“异常血流”或“瓣膜病变”。同时必须说明该判断仅用于医学教学参考，不能替代临床诊断。
输入范围：最大输入为标准心脏超声 12 个体位；最小输入为任意一个体位的收缩态与舒张态。系统已经自动区分收缩态/舒张态，不足时会标注置信度。
请输出一段中文自然语言，包含明确病症判断、教学参考置信度、B-mode 结构依据、Color Doppler 血流依据、当前输入局限性和安全声明。不要输出 JSON，不要分点，输出一段自然语言。
候选判断：${judgment.label}
候选置信度：${judgment.confidence}
候选规则依据：${judgment.rationale}
特征摘要：${study.featureSummary}
紧凑特征：${compactFeatureText(study)}`;
  }

  static classifyTeachingCondition(study: StudyAnalysis): TeachingJudgment {
    const b = study.meanBmode;
    const f = study.meanFlow;
    const edgeDensity = b[5];
    const entropy = b[6];
    const chamberProxy = b[9];
    const dopplerActive = f[4];
    const turbulence = f[5];
    const vorticity = f[8];
    const contractility = study.contractilityProxy;
    const views = new Set<string>(study.frames.map((frame): string => frame.view));
    const hasA4c = views.has('A4C');
    const hasA5c = views.has('A5C');
    const hasA2c = views.has('A2C');
    const hasA3c = views.has('A3C');
    const hasPlax = views.has('PLAX');
    const hasPsaxAv = views.has('PSAX-AV');
    const towards = f[0];
    const away = f[1];
    const signed = f[3];

    const enoughPhase = study.systoleCount >= 1 && study.diastoleCount >= 1;
    const broadCoverage = study.viewCount >= 6;
    const lowEfCalibration = DiagnosisEngine.estimateLowEfCalibration(study);
    const apicalLvView = hasA4c || hasA2c || hasA3c;
    const calibratedLowEfSignal = enoughPhase && apicalLvView && lowEfCalibration.positive;
    const motionLowEfSignal = enoughPhase && study.contractilityFractionProxy < 0.30 && chamberProxy > 0.025;
    let label = '未见明确心脏超声异常';
    let rationale = 'B-mode 结构代理、收缩舒张差异和 Doppler 代理未达到异常阈值。';

    if (dopplerActive > 0.14 && (turbulence > 0.055 || vorticity > 0.045) && (hasPlax || hasA3c)) {
      label = '中度二尖瓣反流';
      rationale = 'PLAX/A3C 相关输入中 Doppler 活跃区和湍流/涡量代理明显升高，教学规则将其归入二尖瓣反流谱系。';
    } else if (dopplerActive > 0.13 && hasA4c && (turbulence > 0.045 || vorticity > 0.04)) {
      label = '中度三尖瓣反流';
      rationale = 'A4C 相关输入中 Doppler 活跃区较高并伴湍流或涡量代理升高，教学规则归入中度三尖瓣反流。';
    } else if (dopplerActive > 0.07 && (hasPlax || hasA3c || hasA2c) && signed < 0.54) {
      label = '轻度二尖瓣反流';
      rationale = '二尖瓣相关切面中出现一定 Doppler 活跃区，方向代理偏向反流侧，但湍流代理未达到中度阈值。';
    } else if (dopplerActive > 0.07 && hasA4c && signed >= 0.54) {
      label = '轻度三尖瓣反流';
      rationale = 'A4C 输入中右心房室区常见反流教学模式与当前 Doppler 方向代理相符，活跃区未达到中重度阈值。';
    } else if (dopplerActive > 0.09 && (hasA5c || hasPsaxAv) && (turbulence > 0.035 || vorticity > 0.035)) {
      label = '主动脉瓣轻度狭窄倾向';
      rationale = 'A5C/主动脉瓣短轴相关输入中出现高速紊流代理，符合主动脉瓣口狭窄教学样例的早期阈值。';
    } else if (dopplerActive > 0.08 && hasA5c && away > towards) {
      label = '轻度主动脉瓣反流';
      rationale = 'A5C 相关输入中 Doppler 方向代理偏离正常射流方向，教学规则将其归入主动脉瓣反流。';
    } else if (dopplerActive > 0.11 && hasPsaxAv && (turbulence > 0.035 || vorticity > 0.035)) {
      label = '肺动脉瓣轻度反流';
      rationale = '主动脉瓣短轴层面附近的流场活跃和涡量代理升高，在当前简化规则中对应肺动脉瓣反流教学标签。';
    } else if (calibratedLowEfSignal || motionLowEfSignal || (enoughPhase && contractility < 0.035 && chamberProxy > 0.035)) {
      label = '左心室收缩功能减低';
      rationale = `PC accuracy baseline: ${lowEfCalibration.compactText}, contractility_fraction_proxy=${study.contractilityFractionProxy.toFixed(3)}, chamber_area_proxy=${chamberProxy.toFixed(3)}.`;
    } else if (edgeDensity > 0.30 || entropy > 0.74) {
      label = '节段性室壁运动异常';
      rationale = 'B-mode 差分矩阵边缘密度或纹理熵偏高，且未达到明确瓣膜反流阈值，教学规则归入室壁运动异常。';
    } else if (dopplerActive > 0.045) {
      label = DiagnosisEngine.defaultMildValveLabel(views, signed, towards, away);
      rationale = 'Doppler 活跃区存在但湍流代理不高，因此输出对应切面的轻度瓣膜反流教学标签。';
    } else if (!enoughPhase) {
      label = '图像证据不足，倾向未见明确异常';
      rationale = '缺少可靠的收缩/舒张配对，当前只能给出低置信度的教学参考判断。';
    }

    let confidence = '低';
    if (broadCoverage && enoughPhase) {
      confidence = '中等';
    } else if (enoughPhase) {
      confidence = '中低';
    }

    return {
      label,
      confidence,
      rationale
    };
  }

  static defaultMildValveLabel(views: Set<string>, signed: number, towards: number, away: number): string {
    if (views.has('A4C') && signed >= 0.52) {
      return '轻度三尖瓣反流';
    }
    if (views.has('PLAX') || views.has('A3C') || views.has('A2C')) {
      return '轻度二尖瓣反流';
    }
    if (views.has('A5C')) {
      return away > towards ? '轻度主动脉瓣反流' : '主动脉瓣轻度狭窄倾向';
    }
    if (views.has('PSAX-AV')) {
      return '肺动脉瓣轻度反流';
    }
    return '轻度二尖瓣反流';
  }

  static heuristicDiagnosis(study: StudyAnalysis, judgment: TeachingJudgment): string {
    const b = study.meanBmode;
    const f = study.meanFlow;
    const lowEfCalibration = DiagnosisEngine.estimateLowEfCalibration(study);
    const calibrationText = judgment.label === '左心室收缩功能减低' ? ` ${lowEfCalibration.compactText}.` : '';
    const viewPhrase = `本次输入包含 ${study.inputCount} 个文件/帧，覆盖约 ${study.viewCount} 个体位`;
    let phasePhrase = `系统自动识别出 ${study.diastoleCount} 个舒张态、${study.systoleCount} 个收缩态`;
    if (study.systoleCount === 0 || study.diastoleCount === 0) {
      phasePhrase += '，收缩/舒张配对不足';
    }
    const structural = `B-mode 边缘密度 ${b[5].toFixed(3)}、纹理熵 ${b[6].toFixed(3)}、收缩舒张腔室面积代理差值 ${study.contractilityProxy.toFixed(3)}、contractility_fraction_proxy ${study.contractilityFractionProxy.toFixed(3)}`;
    const flow = `Color Doppler 活跃区比例 ${f[4].toFixed(3)}、湍流代理 ${f[5].toFixed(3)}、涡量代理 ${f[8].toFixed(3)}`;
    const warning = study.coverageWarning.length > 0 ? ` ${study.coverageWarning}` : '';

    return `教学参考病症判断：${judgment.label}。${viewPhrase}，${phasePhrase}；判断依据为：${judgment.rationale}${structural}；${flow}。综合当前体位覆盖、相位识别和边缘计算特征，本次教学参考置信度为${judgment.confidence}。${calibrationText}${warning}该结论是为了医学教学和算法演示而给出的明确参考判断，不作为临床最终诊断、治疗建议或医嘱；正式判断仍需结合完整标准切面、DICOM 标尺、连续动态帧、病史、体征和超声医师报告。`;
  }

  private static estimateLowEfCalibration(study: StudyAnalysis): LowEfCalibrationEstimate {
    let score = LOW_EF_INTERCEPT;
    for (let index = 0; index < LOW_EF_COEFFS.length; index++) {
      const value = study.meanBmode[index] ?? LOW_EF_MEANS[index];
      score += ((value - LOW_EF_MEANS[index]) / Math.max(LOW_EF_SCALES[index], 0.000001)) * LOW_EF_COEFFS[index];
    }
    const probability = Math.max(0, Math.min(1, DiagnosisEngine.sigmoid(score)));
    return {
      probability,
      threshold: LOW_EF_THRESHOLD,
      positive: probability >= LOW_EF_THRESHOLD,
      compactText: `CAMUS low-EF B-mode calibration p=${probability.toFixed(3)}, threshold=${LOW_EF_THRESHOLD.toFixed(3)}`
    };
  }

  private static sigmoid(score: number): number {
    if (score >= 0) {
      return 1.0 / (1.0 + Math.exp(-score));
    }
    const z = Math.exp(score);
    return z / (1.0 + z);
  }
}
