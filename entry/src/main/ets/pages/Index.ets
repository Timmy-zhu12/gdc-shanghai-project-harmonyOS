import { ImageLoader } from '../model/ImageLoader';
import { FeatureExtractor } from '../model/FeatureExtractor';
import { DiagnosisEngine } from '../model/DiagnosisEngine';
import { ReportExporter } from '../model/ReportExporter';
import { LoadedImage, ModelConfig, RawFile, emptyModelConfig } from '../model/Types';

@Entry
@Component
struct Index {
  private rawFiles: RawFile[] = [];
  private loadedImages: LoadedImage[] = [];

  @State private selectedCount: number = 0;
  @State private frameCount: number = 0;
  @State private busy: boolean = false;
  @State private status: string = '本地规则后备已就绪';
  @State private report: string = '等待导入脱敏心脏超声图像。';
  @State private featureSummary: string = '';
  @State private loadedNames: string[] = [];
  @State private enableGemma4: boolean = false;
  @State private modelPath: string = emptyModelConfig().modelPath;
  @State private mmprojPath: string = emptyModelConfig().mmprojPath;
  @State private maxTokens: string = '640';
  @State private temperature: string = '0.15';

  private async importFiles(): Promise<void> {
    this.busy = true;
    this.status = '正在读取文件';
    try {
      this.rawFiles = await ImageLoader.pickFiles(48);
      this.loadedImages = await ImageLoader.loadImages(this.rawFiles);
      this.selectedCount = this.rawFiles.length;
      this.frameCount = this.loadedImages.length;
      this.loadedNames = this.loadedImages.slice(0, 36).map((item: LoadedImage): string => {
        const suffix = item.frameIndex > 0 ? `#${item.frameIndex}` : '';
        return `${item.name}${suffix} · ${item.sourceType}`;
      });
      this.status = `已载入 ${this.selectedCount} 个文件，解析为 ${this.frameCount} 帧`;
      this.featureSummary = '';
      this.report = '文件已载入，可以开始分析。';
    } catch (error) {
      this.status = `导入失败：${JSON.stringify(error)}`;
      this.report = '导入失败，请检查文件格式是否为 PNG/JPG/BMP/TIFF 或未压缩 Little Endian DICOM/DCOM。';
    } finally {
      this.busy = false;
    }
  }

  private analyze(): void {
    if (this.loadedImages.length === 0) {
      this.status = '请先导入文件';
      return;
    }
    this.busy = true;
    try {
      const study = FeatureExtractor.analyzeLoadedImages(this.loadedImages);
      const result = DiagnosisEngine.runDiagnosis(study, this.currentModelConfig());
      this.report = result.report;
      this.status = result.status;
      this.featureSummary = study.featureSummary;
    } catch (error) {
      this.status = `分析失败：${JSON.stringify(error)}`;
    } finally {
      this.busy = false;
    }
  }

  private async exportReport(): Promise<void> {
    if (this.report.trim().length === 0) {
      this.status = '没有可导出的报告';
      return;
    }
    this.busy = true;
    try {
      this.status = await ReportExporter.exportText(this.report);
    } catch (error) {
      this.status = `导出失败：${JSON.stringify(error)}`;
    } finally {
      this.busy = false;
    }
  }

  private clear(): void {
    this.rawFiles = [];
    this.loadedImages = [];
    this.selectedCount = 0;
    this.frameCount = 0;
    this.loadedNames = [];
    this.featureSummary = '';
    this.report = '等待导入脱敏心脏超声图像。';
    this.status = '本地规则后备已就绪';
  }

  private currentModelConfig(): ModelConfig {
    return {
      enableGemma4: this.enableGemma4,
      nativeBackendName: 'cardio_gemma4_napi',
      modelPath: this.modelPath,
      mmprojPath: this.mmprojPath,
      maxTokens: Number(this.maxTokens) || 640,
      temperature: Number(this.temperature) || 0.15
    };
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Column({ space: 4 }) {
            Text('CardioConsult')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#172026')
            Text('HarmonyOS')
              .fontSize(14)
              .fontColor('#64717A')
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Text(this.busy ? '处理中' : '就绪')
            .fontSize(13)
            .fontColor(this.busy ? '#A65E00' : '#1D6F8F')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(this.busy ? '#FFF1D6' : '#E7F4F8')
            .borderRadius(8)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Column({ space: 12 }) {
          Row({ space: 10 }) {
            Button('导入文件')
              .enabled(!this.busy)
              .layoutWeight(1)
              .height(44)
              .backgroundColor('#1D6F8F')
              .onClick(() => {
                this.importFiles();
              })
            Button('开始分析')
              .enabled(!this.busy && this.frameCount > 0)
              .layoutWeight(1)
              .height(44)
              .backgroundColor('#5C7C4A')
              .onClick(() => {
                this.analyze();
              })
          }
          Row({ space: 10 }) {
            Button('导出报告')
              .enabled(!this.busy && this.report.trim().length > 0)
              .layoutWeight(1)
              .height(40)
              .backgroundColor('#394B59')
              .onClick(() => {
                this.exportReport();
              })
            Button('清空')
              .enabled(!this.busy)
              .layoutWeight(1)
              .height(40)
              .backgroundColor('#8A4D4D')
              .onClick(() => {
                this.clear();
              })
          }

          Row({ space: 8 }) {
            this.statChip('文件', this.selectedCount.toString())
            this.statChip('帧', this.frameCount.toString())
            this.statChip('上限', '12 体位')
          }
          .width('100%')
        }
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .border({ width: 1, color: '#DDE5EA' })

        Column({ space: 10 }) {
          Row() {
            Text('Gemma4 4B')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#172026')
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.enableGemma4 })
              .onChange((isOn: boolean) => {
                this.enableGemma4 = isOn;
              })
          }
          TextInput({ text: this.modelPath, placeholder: 'Gemma4 4B GGUF 路径' })
            .height(42)
            .fontSize(13)
            .onChange((value: string) => {
              this.modelPath = value;
            })
          TextInput({ text: this.mmprojPath, placeholder: '多模态投影文件路径' })
            .height(42)
            .fontSize(13)
            .onChange((value: string) => {
              this.mmprojPath = value;
            })
          Row({ space: 10 }) {
            TextInput({ text: this.maxTokens, placeholder: 'max tokens' })
              .layoutWeight(1)
              .height(40)
              .type(InputType.Number)
              .onChange((value: string) => {
                this.maxTokens = value;
              })
            TextInput({ text: this.temperature, placeholder: 'temperature' })
              .layoutWeight(1)
              .height(40)
              .onChange((value: string) => {
                this.temperature = value;
              })
          }
        }
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .border({ width: 1, color: '#DDE5EA' })

        if (this.loadedNames.length > 0) {
          Column({ space: 8 }) {
            Text('输入队列')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#172026')
            ForEach(this.loadedNames, (name: string) => {
              Text(name)
                .fontSize(13)
                .fontColor('#394B59')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .padding({ top: 4, bottom: 4 })
            }, (name: string) => name)
          }
          .width('100%')
          .padding(14)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .border({ width: 1, color: '#DDE5EA' })
        }

        Column({ space: 10 }) {
          Text('诊断输出')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#172026')
          Text(this.report)
            .fontSize(15)
            .fontColor('#172026')
            .lineHeight(24)
            .width('100%')
            .padding(12)
            .backgroundColor('#F8FAFC')
            .borderRadius(8)
          if (this.featureSummary.length > 0) {
            Text(this.featureSummary)
              .fontSize(12)
              .fontColor('#64717A')
              .lineHeight(18)
              .width('100%')
          }
        }
        .padding(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(8)
        .border({ width: 1, color: '#DDE5EA' })

        Text(this.status)
          .fontSize(13)
          .fontColor('#64717A')
          .lineHeight(18)
          .width('100%')
          .padding({ bottom: 24 })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F6F8FB')
  }

  @Builder
  private statChip(label: string, value: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor('#172026')
      Text(label)
        .fontSize(11)
        .fontColor('#64717A')
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F8FAFC')
    .borderRadius(8)
  }
}
