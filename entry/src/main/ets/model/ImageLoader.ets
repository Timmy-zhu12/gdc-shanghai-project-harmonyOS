import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import { DICOM_EXTENSIONS, LoadedImage, RawFile, SUPPORTED_EXTENSIONS, fileExtension } from './Types';

interface DicomTag {
  group: number;
  element: number;
  vr: string;
  offset: number;
  length: number;
}

interface DicomDataset {
  rows: number;
  columns: number;
  samplesPerPixel: number;
  bitsAllocated: number;
  numberOfFrames: number;
  photometric: string;
  windowCenter: number;
  windowWidth: number;
  pixelOffset: number;
  pixelLength: number;
  metadata: Record<string, string>;
}

const TARGET_SIZE = 256;

export class ImageLoader {
  static async pickFiles(maxSelectNumber: number = 48): Promise<RawFile[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = maxSelectNumber;
    options.fileSuffixFilters = SUPPORTED_EXTENSIONS;
    const documentPicker = new picker.DocumentViewPicker();
    const uris = await documentPicker.select(options);
    const files: RawFile[] = [];
    for (const uri of uris) {
      files.push(await ImageLoader.readRawFile(uri));
    }
    return files;
  }

  static async readRawFile(uri: string): Promise<RawFile> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      const name = ImageLoader.displayNameFromUri(uri);
      return {
        uri,
        name,
        extension: fileExtension(name),
        bytes: new Uint8Array(buffer)
      };
    } finally {
      fs.closeSync(file);
    }
  }

  static async loadImages(rawFiles: RawFile[]): Promise<LoadedImage[]> {
    const loaded: LoadedImage[] = [];
    const errors: string[] = [];
    for (const raw of rawFiles) {
      try {
        if (DICOM_EXTENSIONS.includes(raw.extension)) {
          const dicomFrames = ImageLoader.loadDicom(raw);
          loaded.push(...dicomFrames);
        } else {
          loaded.push(await ImageLoader.loadRaster(raw));
        }
      } catch (error) {
        errors.push(`${raw.name}: ${JSON.stringify(error)}`);
      }
    }
    if (loaded.length === 0 && errors.length > 0) {
      throw new Error(errors.join('\n'));
    }
    return loaded;
  }

  static async loadRaster(raw: RawFile): Promise<LoadedImage> {
    const source = image.createImageSource(raw.bytes.buffer.slice(0));
    const pixelMap = await source.createPixelMap({
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      desiredSize: {
        width: TARGET_SIZE,
        height: TARGET_SIZE
      }
    });
    try {
      const info = await pixelMap.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      const rgbaBuffer = new ArrayBuffer(width * height * 4);
      await pixelMap.readPixelsToBuffer(rgbaBuffer);
      const rgba = new Uint8Array(rgbaBuffer);
      const rgb = new Uint8Array(width * height * 3);
      for (let i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
        rgb[j] = rgba[i];
        rgb[j + 1] = rgba[i + 1];
        rgb[j + 2] = rgba[i + 2];
      }
      return {
        uri: raw.uri,
        name: raw.name,
        frameIndex: 0,
        width,
        height,
        rgb,
        sourceType: 'raster',
        metadata: {}
      };
    } finally {
      pixelMap.release();
      source.release();
    }
  }

  static loadDicom(raw: RawFile): LoadedImage[] {
    const dataset = ImageLoader.parseDicom(raw.bytes);
    if (dataset.pixelOffset <= 0 || dataset.pixelLength <= 0) {
      throw new Error('DICOM has no readable PixelData');
    }
    if (dataset.pixelLength === 0xFFFFFFFF) {
      throw new Error('Compressed or encapsulated DICOM is not supported in this prototype');
    }

    const bytesPerSample = Math.max(1, Math.floor(dataset.bitsAllocated / 8));
    const framePixels = dataset.rows * dataset.columns * dataset.samplesPerPixel;
    const frameBytes = framePixels * bytesPerSample;
    const frames = Math.max(1, Math.min(dataset.numberOfFrames, Math.floor(dataset.pixelLength / Math.max(frameBytes, 1))));
    const out: LoadedImage[] = [];

    for (let frame = 0; frame < frames; frame++) {
      const offset = dataset.pixelOffset + frame * frameBytes;
      const rgb = ImageLoader.dicomFrameToRgb(raw.bytes, offset, dataset);
      out.push({
        uri: raw.uri,
        name: raw.name,
        frameIndex: frame,
        width: TARGET_SIZE,
        height: TARGET_SIZE,
        rgb: ImageLoader.resizeRgbNearest(rgb, dataset.columns, dataset.rows, TARGET_SIZE, TARGET_SIZE),
        sourceType: 'dicom',
        metadata: dataset.metadata
      });
    }
    return out;
  }

  private static parseDicom(bytes: Uint8Array): DicomDataset {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let offset = 0;
    if (bytes.byteLength > 132 && ImageLoader.ascii(bytes, 128, 4) === 'DICM') {
      offset = 132;
    }

    const dataset: DicomDataset = {
      rows: 0,
      columns: 0,
      samplesPerPixel: 1,
      bitsAllocated: 8,
      numberOfFrames: 1,
      photometric: 'MONOCHROME2',
      windowCenter: 0,
      windowWidth: 0,
      pixelOffset: -1,
      pixelLength: -1,
      metadata: {}
    };

    while (offset + 8 <= bytes.byteLength) {
      const tag = ImageLoader.readTag(bytes, view, offset);
      if (tag.length < 0 || tag.offset + tag.length > bytes.byteLength) {
        break;
      }
      const key = ImageLoader.tagKey(tag.group, tag.element);
      const valueText = ImageLoader.textValue(bytes, tag.offset, tag.length);

      if (key === '0028,0010') {
        dataset.rows = ImageLoader.usValue(bytes, tag.offset);
      } else if (key === '0028,0011') {
        dataset.columns = ImageLoader.usValue(bytes, tag.offset);
      } else if (key === '0028,0002') {
        dataset.samplesPerPixel = Math.max(1, ImageLoader.usValue(bytes, tag.offset));
      } else if (key === '0028,0100') {
        dataset.bitsAllocated = Math.max(8, ImageLoader.usValue(bytes, tag.offset));
      } else if (key === '0028,0008') {
        dataset.numberOfFrames = Math.max(1, Math.floor(ImageLoader.numberValue(valueText, 1)));
      } else if (key === '0028,0004') {
        dataset.photometric = valueText.toUpperCase();
      } else if (key === '0028,1050') {
        dataset.windowCenter = ImageLoader.numberValue(valueText, 0);
      } else if (key === '0028,1051') {
        dataset.windowWidth = ImageLoader.numberValue(valueText, 0);
      } else if (key === '0010,0020') {
        dataset.metadata.PatientID = valueText;
      } else if (key === '0008,0020') {
        dataset.metadata.StudyDate = valueText;
      } else if (key === '0008,1030') {
        dataset.metadata.StudyDescription = valueText;
      } else if (key === '0008,103E') {
        dataset.metadata.SeriesDescription = valueText;
      } else if (key === '0008,0060') {
        dataset.metadata.Modality = valueText;
      } else if (key === '7FE0,0010') {
        dataset.pixelOffset = tag.offset;
        dataset.pixelLength = tag.length;
        break;
      }
      offset = tag.offset + tag.length;
    }

    if (dataset.rows <= 0 || dataset.columns <= 0) {
      throw new Error('DICOM rows or columns missing');
    }
    return dataset;
  }

  private static readTag(bytes: Uint8Array, view: DataView, offset: number): DicomTag {
    const group = view.getUint16(offset, true);
    const element = view.getUint16(offset + 2, true);
    let vr = ImageLoader.ascii(bytes, offset + 4, 2);
    let valueOffset = offset + 8;
    let length = 0;
    const explicit = /^[A-Z]{2}$/.test(vr);
    if (explicit) {
      const longVr = ['OB', 'OD', 'OF', 'OL', 'OW', 'SQ', 'UC', 'UR', 'UT', 'UN'].includes(vr);
      if (longVr) {
        length = view.getUint32(offset + 8, true);
        valueOffset = offset + 12;
      } else {
        length = view.getUint16(offset + 6, true);
      }
    } else {
      vr = 'UN';
      length = view.getUint32(offset + 4, true);
      valueOffset = offset + 8;
    }
    if (length === 0xFFFFFFFF) {
      return {
        group,
        element,
        vr,
        offset: valueOffset,
        length
      };
    }
    return {
      group,
      element,
      vr,
      offset: valueOffset,
      length
    };
  }

  private static dicomFrameToRgb(bytes: Uint8Array, offset: number, dataset: DicomDataset): Uint8Array {
    const pixelCount = dataset.rows * dataset.columns;
    const rgb = new Uint8Array(pixelCount * 3);
    if (dataset.samplesPerPixel >= 3 && dataset.bitsAllocated === 8) {
      for (let i = 0; i < pixelCount; i++) {
        const source = offset + i * dataset.samplesPerPixel;
        const target = i * 3;
        rgb[target] = bytes[source];
        rgb[target + 1] = bytes[source + 1];
        rgb[target + 2] = bytes[source + 2];
      }
      return rgb;
    }

    const values: number[] = new Array(pixelCount);
    let minValue = Number.POSITIVE_INFINITY;
    let maxValue = Number.NEGATIVE_INFINITY;
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    for (let i = 0; i < pixelCount; i++) {
      const sampleOffset = offset + i * Math.max(1, Math.floor(dataset.bitsAllocated / 8));
      const value = dataset.bitsAllocated <= 8 ? bytes[sampleOffset] : view.getUint16(sampleOffset, true);
      values[i] = value;
      minValue = Math.min(minValue, value);
      maxValue = Math.max(maxValue, value);
    }

    let low = minValue;
    let high = maxValue;
    if (dataset.windowCenter !== 0 && dataset.windowWidth > 1) {
      low = dataset.windowCenter - dataset.windowWidth / 2;
      high = dataset.windowCenter + dataset.windowWidth / 2;
    }

    for (let i = 0; i < pixelCount; i++) {
      let scaled = Math.round(((values[i] - low) / Math.max(high - low, 1)) * 255);
      scaled = Math.max(0, Math.min(255, scaled));
      if (dataset.photometric === 'MONOCHROME1') {
        scaled = 255 - scaled;
      }
      const target = i * 3;
      rgb[target] = scaled;
      rgb[target + 1] = scaled;
      rgb[target + 2] = scaled;
    }
    return rgb;
  }

  private static resizeRgbNearest(source: Uint8Array, sourceWidth: number, sourceHeight: number, targetWidth: number, targetHeight: number): Uint8Array {
    const target = new Uint8Array(targetWidth * targetHeight * 3);
    for (let y = 0; y < targetHeight; y++) {
      const sy = Math.min(sourceHeight - 1, Math.floor((y / targetHeight) * sourceHeight));
      for (let x = 0; x < targetWidth; x++) {
        const sx = Math.min(sourceWidth - 1, Math.floor((x / targetWidth) * sourceWidth));
        const src = (sy * sourceWidth + sx) * 3;
        const dst = (y * targetWidth + x) * 3;
        target[dst] = source[src];
        target[dst + 1] = source[src + 1];
        target[dst + 2] = source[src + 2];
      }
    }
    return target;
  }

  private static displayNameFromUri(uri: string): string {
    const clean = decodeURIComponent(uri.split('?')[0]);
    const slash = Math.max(clean.lastIndexOf('/'), clean.lastIndexOf('\\'));
    return slash >= 0 ? clean.substring(slash + 1) : clean;
  }

  private static ascii(bytes: Uint8Array, offset: number, length: number): string {
    let text = '';
    for (let i = 0; i < length && offset + i < bytes.length; i++) {
      text += String.fromCharCode(bytes[offset + i]);
    }
    return text;
  }

  private static textValue(bytes: Uint8Array, offset: number, length: number): string {
    let text = '';
    const safeLength = Math.max(0, Math.min(length, bytes.length - offset));
    for (let i = 0; i < safeLength; i++) {
      const value = bytes[offset + i];
      if (value !== 0) {
        text += String.fromCharCode(value);
      }
    }
    return text.trim().replace('\\', ',');
  }

  private static usValue(bytes: Uint8Array, offset: number): number {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    return view.getUint16(offset, true);
  }

  private static numberValue(text: string, fallback: number): number {
    const first = text.split(',')[0].trim();
    const value = Number(first);
    return Number.isFinite(value) ? value : fallback;
  }

  private static tagKey(group: number, element: number): string {
    return `${group.toString(16).toUpperCase().padStart(4, '0')},${element.toString(16).toUpperCase().padStart(4, '0')}`;
  }
}
