import { FrameAnalysis, LoadedImage, StudyAnalysis, fileStem } from './Types';

const STANDARD_VIEWS: Array<[string, string[]]> = [
  ['PLAX', ['plax', 'parasternal_long', 'long_axis', '左室长轴', '胸骨旁长轴']],
  ['PSAX-AV', ['psax_av', 'aortic_valve', 'short_axis_av', '主动脉瓣短轴']],
  ['PSAX-MV', ['psax_mv', 'mitral', '二尖瓣短轴']],
  ['PSAX-PM', ['psax_pm', 'papillary', '乳头肌短轴']],
  ['PSAX-APEX', ['psax_apex', 'apex_short', '心尖短轴']],
  ['A4C', ['a4c', 'apical_4', 'four_chamber', '心尖四腔']],
  ['A5C', ['a5c', 'apical_5', 'five_chamber', '心尖五腔']],
  ['A2C', ['a2c', 'apical_2', 'two_chamber', '心尖二腔']],
  ['A3C', ['a3c', 'apical_3', 'three_chamber', '心尖三腔']],
  ['SUBCOSTAL-4C', ['subcostal', 'subxiphoid', '剑突下', '肋下']],
  ['IVC', ['ivc', '下腔静脉']],
  ['SUPRASTERNAL', ['suprasternal', 'arch', '胸骨上窝', '主动脉弓']]
];

export class FeatureExtractor {
  static analyzeLoadedImages(images: LoadedImage[]): StudyAnalysis {
    if (images.length === 0) {
      throw new Error('No input images were loaded');
    }

    const provisional: FrameAnalysis[] = [];
    for (const loaded of images) {
      const gray = FeatureExtractor.rgbToGray(loaded.rgb, loaded.width, loaded.height);
      const bmode = FeatureExtractor.bmodeFeatures(gray, loaded.width, loaded.height);
      const flow = FeatureExtractor.flowFeatures(loaded.rgb, loaded.width, loaded.height);
      provisional.push({
        loaded,
        view: FeatureExtractor.detectView(loaded.name),
        phase: FeatureExtractor.phaseFromName(loaded.name),
        chamberAreaProxy: FeatureExtractor.chamberAreaProxy(gray, loaded.width, loaded.height),
        hasColorDoppler: flow[4] > 0.015,
        bmodeFeatures: bmode,
        flowFeatures: flow,
        notes: ''
      });
    }

    const frames = FeatureExtractor.assignPhases(provisional);
    const viewSet = new Set<string>();
    let systole = 0;
    let diastole = 0;
    for (const frame of frames) {
      viewSet.add(frame.view);
      if (frame.phase === 'systole') {
        systole++;
      } else if (frame.phase === 'diastole') {
        diastole++;
      }
    }

    const meanB = FeatureExtractor.meanVector(frames.map((frame: FrameAnalysis): number[] => frame.bmodeFeatures), 10);
    const meanF = FeatureExtractor.meanVector(frames.map((frame: FrameAnalysis): number[] => frame.flowFeatures), 10);
    const contractility = FeatureExtractor.computeContractilityProxy(frames);
    let warning = '';
    if (viewSet.size > 12) {
      warning = '输入超过 12 个体位标签，已按全部文件聚合；建议按标准 12 体位整理。';
    } else if (viewSet.size < 2) {
      warning = '体位覆盖较少，输出只能作为较低置信度的疑似教学判断。';
    }

    return {
      frames,
      viewCount: viewSet.size,
      inputCount: images.length,
      systoleCount: systole,
      diastoleCount: diastole,
      meanBmode: meanB,
      meanFlow: meanF,
      contractilityProxy: contractility,
      coverageWarning: warning,
      featureSummary: FeatureExtractor.buildFeatureSummary(frames, meanB, meanF, contractility, warning)
    };
  }

  static rgbToGray(rgb: Uint8Array, width: number, height: number): number[] {
    const gray = new Array<number>(width * height);
    for (let i = 0, j = 0; i < gray.length; i++, j += 3) {
      gray[i] = (0.299 * rgb[j] + 0.587 * rgb[j + 1] + 0.114 * rgb[j + 2]) / 255.0;
    }
    return gray;
  }

  static bmodeFeatures(gray: number[], width: number, height: number): number[] {
    const normalized = FeatureExtractor.robustNormalize(gray);
    const dog = FeatureExtractor.dogEnhance(normalized, width, height);
    let dxSum = 0;
    let dySum = 0;
    let gradSum = 0;
    let gradActive = 0;
    let countDx = 0;
    let countDy = 0;
    let gradCount = 0;
    const hist = new Array<number>(32).fill(0);

    let mean = 0;
    for (const value of normalized) {
      mean += value;
      const bin = Math.max(0, Math.min(31, Math.floor(value * 32)));
      hist[bin]++;
    }
    mean /= Math.max(normalized.length, 1);

    let variance = 0;
    for (const value of normalized) {
      const diff = value - mean;
      variance += diff * diff;
    }
    variance /= Math.max(normalized.length, 1);

    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const index = y * width + x;
        if (x + 1 < width) {
          dxSum += Math.abs(normalized[index + 1] - normalized[index]);
          countDx++;
        }
        if (y + 1 < height) {
          dySum += Math.abs(normalized[index + width] - normalized[index]);
          countDy++;
        }
        if (x + 1 < width && y + 1 < height) {
          const dx = normalized[index + 1] - normalized[index];
          const dy = normalized[index + width] - normalized[index];
          const grad = Math.sqrt(dx * dx + dy * dy);
          gradSum += grad;
          if (grad > 0.12) {
            gradActive++;
          }
          gradCount++;
        }
      }
    }

    let dogMean = 0;
    let dogHigh = 0;
    for (const value of dog) {
      dogMean += value;
      if (value > 0.65) {
        dogHigh++;
      }
    }
    dogMean /= Math.max(dog.length, 1);

    return [
      mean,
      variance,
      dxSum / Math.max(countDx, 1),
      dySum / Math.max(countDy, 1),
      gradSum / Math.max(gradCount, 1),
      gradActive / Math.max(gradCount, 1),
      FeatureExtractor.normalizedEntropy(hist),
      dogMean,
      dogHigh / Math.max(dog.length, 1),
      FeatureExtractor.chamberAreaProxy(normalized, width, height)
    ];
  }

  static flowFeatures(rgb: Uint8Array, width: number, height: number): number[] {
    const pixelCount = width * height;
    const vx = new Array<number>(pixelCount).fill(0);
    const vy = new Array<number>(pixelCount).fill(0);
    const speed = new Array<number>(pixelCount).fill(0);
    let activeCount = 0;
    let towards = 0;
    let away = 0;
    let speedSum = 0;
    let vxSum = 0;

    for (let i = 0, j = 0; i < pixelCount; i++, j += 3) {
      const hsv = FeatureExtractor.rgbToHsv(rgb[j], rgb[j + 1], rgb[j + 2]);
      const localSpeed = hsv[1] * hsv[2];
      speed[i] = localSpeed;
      if (localSpeed > 0.12) {
        const theta = FeatureExtractor.hueToTheta(hsv[0]);
        vx[i] = localSpeed * Math.cos(theta);
        vy[i] = localSpeed * Math.sin(theta);
        if (vx[i] >= 0) {
          towards++;
        } else {
          away++;
        }
        speedSum += localSpeed;
        vxSum += vx[i];
        activeCount++;
      }
    }

    const safeActive = Math.max(activeCount, 1);
    let variance = 0;
    if (activeCount > 0) {
      const meanSpeed = speedSum / safeActive;
      for (const value of speed) {
        if (value > 0.12) {
          const diff = value - meanSpeed;
          variance += diff * diff;
        }
      }
      variance /= safeActive;
    }

    let gradX = 0;
    let gradY = 0;
    let gradXCount = 0;
    let gradYCount = 0;
    let divergence = 0;
    let vorticity = 0;
    let vectorCells = 0;
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const index = y * width + x;
        if (x + 1 < width) {
          gradX += Math.abs(vx[index + 1] - vx[index]);
          gradXCount++;
        }
        if (y + 1 < height) {
          gradY += Math.abs(vy[index + width] - vy[index]);
          gradYCount++;
        }
        if (x + 1 < width && y + 1 < height) {
          const dvx = vx[index + 1] - vx[index];
          const dvy = vy[index + width] - vy[index];
          const curlY = vy[index + 1] - vy[index];
          const curlX = vx[index + width] - vx[index];
          divergence += Math.abs(dvx + dvy);
          vorticity += Math.abs(curlY - curlX);
          vectorCells++;
        }
      }
    }

    return [
      towards / safeActive,
      away / safeActive,
      speedSum / safeActive,
      vxSum / safeActive * 0.5 + 0.5,
      activeCount / Math.max(pixelCount, 1),
      variance,
      ((gradX / Math.max(gradXCount, 1)) + (gradY / Math.max(gradYCount, 1))) / 2,
      divergence / Math.max(vectorCells, 1),
      vorticity / Math.max(vectorCells, 1),
      speedSum / safeActive
    ];
  }

  static chamberAreaProxy(gray: number[], width: number, height: number): number {
    const x0 = Math.floor(width * 0.12);
    const x1 = Math.floor(width * 0.88);
    const y0 = Math.floor(height * 0.18);
    const y1 = Math.floor(height * 0.86);
    const crop: number[] = [];
    for (let y = y0; y < y1; y++) {
      for (let x = x0; x < x1; x++) {
        crop.push(gray[y * width + x]);
      }
    }
    const threshold = FeatureExtractor.otsuThreshold(crop);
    const cropWidth = Math.max(1, x1 - x0);
    const cropHeight = Math.max(1, y1 - y0);
    const cx = (cropWidth - 1) / 2;
    const cy = (cropHeight - 1) / 2;
    let darkWeighted = 0;
    let weightSum = 0;
    for (let y = 0; y < cropHeight; y++) {
      for (let x = 0; x < cropWidth; x++) {
        const index = y * cropWidth + x;
        const radius = Math.sqrt(((y - cy) / cropHeight) ** 2 + ((x - cx) / cropWidth) ** 2);
        const weight = Math.max(0.15, Math.min(1, 1 - radius * 2.2));
        if (crop[index] < threshold) {
          darkWeighted += weight;
        }
        weightSum += weight;
      }
    }
    return darkWeighted / Math.max(weightSum, 1);
  }

  static robustNormalize(values: number[]): number[] {
    const sorted = values.slice().sort((a: number, b: number): number => a - b);
    const low = FeatureExtractor.percentileFromSorted(sorted, 2);
    const high = FeatureExtractor.percentileFromSorted(sorted, 98);
    const denom = Math.max(high - low, 0.000001);
    return values.map((value: number): number => Math.max(0, Math.min(1, (value - low) / denom)));
  }

  static dogEnhance(gray: number[], width: number, height: number): number[] {
    const blur1 = FeatureExtractor.boxBlur(gray, width, height, 1);
    const blur2 = FeatureExtractor.boxBlur(gray, width, height, 2);
    const dog = new Array<number>(gray.length);
    for (let i = 0; i < gray.length; i++) {
      dog[i] = blur1[i] - blur2[i];
    }
    return FeatureExtractor.robustNormalize(dog);
  }

  static boxBlur(values: number[], width: number, height: number, radius: number): number[] {
    const out = new Array<number>(values.length).fill(0);
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        let sum = 0;
        let count = 0;
        for (let yy = Math.max(0, y - radius); yy <= Math.min(height - 1, y + radius); yy++) {
          for (let xx = Math.max(0, x - radius); xx <= Math.min(width - 1, x + radius); xx++) {
            sum += values[yy * width + xx];
            count++;
          }
        }
        out[y * width + x] = sum / Math.max(count, 1);
      }
    }
    return out;
  }

  static otsuThreshold(values: number[]): number {
    const hist = new Array<number>(96).fill(0);
    for (const value of values) {
      const bin = Math.max(0, Math.min(95, Math.floor(Math.max(0, Math.min(1, value)) * 96)));
      hist[bin]++;
    }
    const total = values.length;
    if (total <= 0) {
      return 0.25;
    }
    let sumTotal = 0;
    for (let i = 0; i < hist.length; i++) {
      const center = (i + 0.5) / 96.0;
      sumTotal += hist[i] * center;
    }
    let weightBg = 0;
    let sumBg = 0;
    let bestVar = -1;
    let best = 0.25;
    for (let i = 0; i < hist.length; i++) {
      const center = (i + 0.5) / 96.0;
      weightBg += hist[i];
      if (weightBg <= 0) {
        continue;
      }
      const weightFg = total - weightBg;
      if (weightFg <= 0) {
        break;
      }
      sumBg += hist[i] * center;
      const meanBg = sumBg / weightBg;
      const meanFg = (sumTotal - sumBg) / weightFg;
      const between = weightBg * weightFg * (meanBg - meanFg) * (meanBg - meanFg);
      if (between > bestVar) {
        bestVar = between;
        best = center;
      }
    }
    return Math.max(0.08, Math.min(0.55, best));
  }

  static normalizedEntropy(hist: number[]): number {
    const total = hist.reduce((sum: number, value: number): number => sum + value, 0);
    if (total <= 0) {
      return 0;
    }
    let entropy = 0;
    for (const count of hist) {
      if (count > 0) {
        const p = count / total;
        entropy -= p * Math.log2(p);
      }
    }
    return Math.max(0, Math.min(1, entropy / 5.0));
  }

  static rgbToHsv(rByte: number, gByte: number, bByte: number): number[] {
    const r = rByte / 255.0;
    const g = gByte / 255.0;
    const b = bByte / 255.0;
    const maxc = Math.max(r, g, b);
    const minc = Math.min(r, g, b);
    const delta = maxc - minc;
    let hue = 0;
    if (delta > 0.000001) {
      if (maxc === r) {
        hue = (((g - b) / delta) % 6) * 60;
      } else if (maxc === g) {
        hue = (((b - r) / delta) + 2) * 60;
      } else {
        hue = (((r - g) / delta) + 4) * 60;
      }
      if (hue < 0) {
        hue += 360;
      }
    }
    const saturation = maxc <= 0.000001 ? 0 : delta / Math.max(maxc, 0.000001);
    return [hue, saturation, maxc];
  }

  static hueToTheta(hue: number): number {
    if (hue <= 240.0) {
      return (hue / 240.0) * Math.PI;
    }
    if (hue > 240.0 && hue < 330.0) {
      return Math.PI + ((hue - 240.0) / 90.0) * Math.PI;
    }
    return 0.0;
  }

  static detectView(name: string): string {
    const stem = fileStem(name).toLowerCase();
    for (const item of STANDARD_VIEWS) {
      const view = item[0];
      const keywords = item[1];
      for (const keyword of keywords) {
        if (stem.includes(keyword.toLowerCase())) {
          return view;
        }
      }
    }
    return 'UNKNOWN';
  }

  static phaseFromName(name: string): string {
    const stem = fileStem(name).toLowerCase();
    const systoleKeys = ['systole', 'systolic', '_es', '-es', 'endsystole', 'end_systole', '收缩'];
    const diastoleKeys = ['diastole', 'diastolic', '_ed', '-ed', 'enddiastole', 'end_diastole', '舒张'];
    for (const key of systoleKeys) {
      if (stem.includes(key)) {
        return 'systole';
      }
    }
    for (const key of diastoleKeys) {
      if (stem.includes(key)) {
        return 'diastole';
      }
    }
    return 'unknown';
  }

  static assignPhases(frames: FrameAnalysis[]): FrameAnalysis[] {
    const byView = new Map<string, FrameAnalysis[]>();
    for (const frame of frames) {
      if (!byView.has(frame.view)) {
        byView.set(frame.view, []);
      }
      byView.get(frame.view)?.push(frame);
    }

    byView.forEach((group: FrameAnalysis[]) => {
      const hasUnknown = group.some((frame: FrameAnalysis): boolean => frame.phase === 'unknown');
      if (group.length >= 2 && hasUnknown) {
        const ordered = group.slice().sort((a: FrameAnalysis, b: FrameAnalysis): number => a.chamberAreaProxy - b.chamberAreaProxy);
        ordered[0].phase = 'systole';
        ordered[ordered.length - 1].phase = 'diastole';
        for (let i = 1; i < ordered.length - 1; i++) {
          if (ordered[i].phase === 'unknown') {
            ordered[i].phase = 'intermediate';
          }
        }
      } else if (group.length === 1 && group[0].phase === 'unknown') {
        group[0].phase = 'unknown_single_frame';
      }
    });
    return frames;
  }

  static computeContractilityProxy(frames: FrameAnalysis[]): number {
    const byView = new Map<string, FrameAnalysis[]>();
    for (const frame of frames) {
      if (!byView.has(frame.view)) {
        byView.set(frame.view, []);
      }
      byView.get(frame.view)?.push(frame);
    }
    const deltas: number[] = [];
    byView.forEach((group: FrameAnalysis[]) => {
      const systolic = group.filter((frame: FrameAnalysis): boolean => frame.phase === 'systole').map((frame: FrameAnalysis): number => frame.chamberAreaProxy);
      const diastolic = group.filter((frame: FrameAnalysis): boolean => frame.phase === 'diastole').map((frame: FrameAnalysis): number => frame.chamberAreaProxy);
      if (systolic.length > 0 && diastolic.length > 0) {
        deltas.push(Math.max(...diastolic) - Math.min(...systolic));
      }
    });
    if (deltas.length === 0) {
      return 0;
    }
    return deltas.reduce((sum: number, value: number): number => sum + value, 0) / deltas.length;
  }

  static meanVector(vectors: number[][], length: number): number[] {
    const out = new Array<number>(length).fill(0);
    if (vectors.length === 0) {
      return out;
    }
    for (const vector of vectors) {
      for (let i = 0; i < length; i++) {
        out[i] += vector[i] ?? 0;
      }
    }
    for (let i = 0; i < length; i++) {
      out[i] /= vectors.length;
    }
    return out;
  }

  static buildFeatureSummary(frames: FrameAnalysis[], meanB: number[], meanF: number[], contractility: number, warning: string): string {
    const views = Array.from(new Set<string>(frames.map((frame: FrameAnalysis): string => frame.view))).sort().join(', ');
    const phaseText = frames.slice(0, 24)
      .map((frame: FrameAnalysis): string => `${frame.loaded.name}${frame.loaded.frameIndex > 0 ? `#${frame.loaded.frameIndex}` : ''}:${frame.phase}/${frame.view}`)
      .join(', ');
    return `输入 ${frames.length} 个文件/帧，覆盖体位: ${views}. 相位识别: ${phaseText}. 收缩-舒张腔室面积代理差值 ${contractility.toFixed(3)}. B-mode 边缘密度=${meanB[5].toFixed(3)}, 纹理熵=${meanB[6].toFixed(3)}; Doppler 活跃区比例=${meanF[4].toFixed(3)}, 湍流代理=${meanF[5].toFixed(3)}, 涡量代理=${meanF[8].toFixed(3)}. ${warning}`.trim();
  }

  private static percentileFromSorted(sorted: number[], percentile: number): number {
    if (sorted.length === 0) {
      return 0;
    }
    const position = (percentile / 100) * (sorted.length - 1);
    const lower = Math.floor(position);
    const upper = Math.ceil(position);
    if (lower === upper) {
      return sorted[lower];
    }
    const weight = position - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  }
}
