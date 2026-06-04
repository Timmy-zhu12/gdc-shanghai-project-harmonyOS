# CardioConsult HarmonyOS 版中文说明

CardioConsult HarmonyOS 是基于 PC 版 CardioConsult 迁移出的华为 HarmonyOS 设备版本。项目面向医学教学、算法演示和 GDG/GDC 类比赛原型，不作为临床诊断、治疗建议或医嘱。

本版本保留 PC 版的核心功能逻辑：批量导入脱敏心脏超声 PNG/JPG/BMP/TIFF 与 DICOM/DCOM 文件，最多按标准心脏超声 12 个体位聚合，最少可从任意一个体位的收缩态与舒张态开始分析，自动区分收缩/舒张相位，提取 B-mode 差分矩阵特征和 Color Doppler 血流向量特征，并输出精确到病症名称的中文教学参考判断。

## 功能概览

- HarmonyOS Stage 模型工程，可用 DevEco Studio 打开。
- ArkTS + SwiftUI 类似的声明式界面，适配华为手机、平板和 2in1 设备。
- 支持用户主动选择多个文件。
- 支持 `.png`、`.jpg`、`.jpeg`、`.bmp`、`.tif`、`.tiff`。
- 支持 `.dcm`、`.dicom`、`.dcom` 的轻量解析。
- 支持未压缩 Little Endian DICOM 像素数据和多帧 DICOM 拆分。
- 支持标准心脏超声 12 体位标签识别。
- 支持收缩态/舒张态自动判断。
- 支持 B-mode 差分、边缘密度、纹理熵、DoG 代理和腔室面积代理。
- 支持 Color Doppler HSV 血流向量化、活跃区比例、湍流代理、散度和涡量代理。
- 支持 Gemma4 4B 离线推理接口。
- Gemma4 native 后端缺失时仍可运行，自动使用本地规则后备。
- 输出具体病症判断，例如轻度二尖瓣反流、轻度三尖瓣反流、主动脉瓣轻度狭窄倾向、左心室收缩功能减低等。
- 支持导出 TXT 报告。

## 仓库位置

本地目录：

```text
D:\cardioconsult_HarmonyOS_runbook
```

GitHub：

```text
https://github.com/Timmy-zhu12/gdc-shanghai-project-harmonyOS
```

## 目录结构

```text
cardioconsult_HarmonyOS_runbook/
├── AppScope/
│   └── app.json5
├── entry/
│   ├── build-profile.json5
│   ├── hvigorfile.ts
│   ├── oh-package.json5
│   └── src/main/
│       ├── cpp/
│       │   ├── CMakeLists.txt
│       │   ├── napi_init.cpp
│       │   └── types/libcardio_gemma4/
│       ├── ets/
│       │   ├── entryability/EntryAbility.ets
│       │   ├── model/
│       │   │   ├── DiagnosisEngine.ets
│       │   │   ├── FeatureExtractor.ets
│       │   │   ├── Gemma4Bridge.ets
│       │   │   ├── ImageLoader.ets
│       │   │   ├── ReportExporter.ets
│       │   │   └── Types.ets
│       │   └── pages/Index.ets
│       └── resources/
├── docs/
│   ├── algorithm.md
│   └── native_gemma4_backend.md
├── scripts/
│   └── static_check.ps1
├── build-profile.json5
├── hvigorfile.ts
├── oh-package.json5
└── README.md
```

## 部署环境

推荐环境：

- DevEco Studio
- HarmonyOS SDK / API 12 或兼容版本
- HarmonyOS 真机或模拟器
- 8 GB RAM 起步，推荐 16 GB 或更高
- 如需本地 Gemma4 4B GGUF，设备需要足够存储与内存

当前仓库已经包含可运行的本地规则诊断流程。真正的 Gemma4 4B 设备端推理需要把 llama.cpp 或等价 GGUF 推理后端编译为 HarmonyOS NAPI native 模块。

## 用 DevEco Studio 打开

1. 打开 DevEco Studio。
2. 选择 `Open Project`。
3. 打开：

```text
D:\cardioconsult_HarmonyOS_runbook
```

4. 等待 `oh-package.json5` 和 Hvigor 工程同步。
5. 选择 `entry` 模块。
6. 连接华为 HarmonyOS 设备或启动模拟器。
7. 点击 Run。

如果签名配置缺失，请在 DevEco Studio 的 signing 配置页面创建调试签名，再重新运行。

## 使用流程

1. 启动 CardioConsult。
2. 点击“导入文件”。
3. 选择脱敏后的心脏超声 PNG/JPG/BMP/TIFF 或 DICOM/DCOM 文件。
4. 点击“开始分析”。
5. 查看“诊断输出”中的中文教学参考判断。
6. 点击“导出报告”保存 TXT。

推荐文件名包含体位和相位信息，例如：

```text
A4C_ED.png
A4C_ES.png
PLAX_ED.png
PLAX_ES.png
A5C_color_doppler.png
```

相位关键词：

```text
ED, ES, diastole, systole, end_diastole, end_systole, 舒张, 收缩
```

体位关键词：

```text
PLAX, PSAX-AV, PSAX-MV, PSAX-PM, PSAX-APEX, A4C, A5C, A2C, A3C, SUBCOSTAL-4C, IVC, SUPRASTERNAL
```

## 离线 Gemma4 4B

HarmonyOS 版保留与 PC 版一致的 Gemma4 4B prompt 合同和诊断入口。UI 中可以填写：

```text
/data/storage/el2/base/files/models/gemma-4-4b-it-Q4_K_M.gguf
/data/storage/el2/base/files/models/gemma-4-4b-mmproj-Q4_0.gguf
```

当前仓库内置的 `libcardio_gemma4.so` 是安全 stub，作用是让项目可构建、可运行，并在 native 后端尚未接入时自动转入本地规则后备。真正启用离线 Gemma4 4B 时，需要参考 `docs/native_gemma4_backend.md` 替换 C++ NAPI 实现。

不建议把 GGUF 文件提交到 GitHub。本仓库已经在 `.gitignore` 中排除了模型大文件。

## 输出示例

```text
教学参考病症判断：轻度二尖瓣反流。本次输入包含 4 个文件/帧，覆盖约 2 个体位，系统自动识别出 2 个舒张态、2 个收缩态；判断依据为：二尖瓣相关切面中出现一定 Doppler 活跃区，方向代理偏向反流侧，但湍流代理未达到中度阈值。B-mode 边缘密度 0.086、纹理熵 0.622、收缩舒张腔室面积代理差值 0.118；Color Doppler 活跃区比例 0.082、湍流代理 0.026、涡量代理 0.018。综合当前体位覆盖、相位识别和边缘计算特征，本次教学参考置信度为中低。该结论是为了医学教学和算法演示而给出的明确参考判断，不作为临床最终诊断、治疗建议或医嘱。
```

## 已知限制

- 本项目是医学教学辅助工具，不是医疗器械。
- 未压缩 Little Endian DICOM 支持较好，压缩 DICOM、封装视频和厂商私有格式可能无法解析。
- Color Doppler 的真实速度标尺、Nyquist limit、探头角度、aliasing 和增益没有完整建模。
- 如果只输入单张图像，系统仍会输出判断，但置信度会降低。
- Gemma4 4B 的真实设备端离线推理依赖 native 后端、设备内存和量化模型文件。

## 静态检查

在 Windows PowerShell 中运行：

```powershell
Set-Location D:\cardioconsult_HarmonyOS_runbook
powershell -ExecutionPolicy Bypass -File .\scripts\static_check.ps1
```

该脚本会检查关键工程文件是否存在，并确认没有遗留旧模型名。

## 许可证

本仓库原创代码、脚本、UI、配置与文档采用 Apache License 2.0 发布，详见 [LICENSE](LICENSE)。

注意：该许可证不覆盖第三方模型权重、GGUF 文件、移动/桌面系统 SDK、超声软件、医学影像数据集、第三方商标或用户提供的教学/临床数据；这些内容仍受其各自许可、平台条款或伦理/机构授权约束。详细边界见 [NOTICE](NOTICE)。
