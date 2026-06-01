import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

export class ReportExporter {
  static async exportText(report: string): Promise<string> {
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`CardioConsult_${ReportExporter.timestamp()}.txt`];
    const documentPicker = new picker.DocumentViewPicker();
    const uris = await documentPicker.save(options);
    if (uris.length === 0) {
      return '未选择保存位置';
    }

    const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      const encoder = new util.TextEncoder();
      const encoded = encoder.encodeInto(report);
      fs.writeSync(file.fd, encoded.buffer);
    } finally {
      fs.closeSync(file);
    }
    return `报告已导出：${uris[0]}`;
  }

  private static timestamp(): string {
    const now = new Date();
    const pad = (value: number): string => value.toString().padStart(2, '0');
    return `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  }
}
