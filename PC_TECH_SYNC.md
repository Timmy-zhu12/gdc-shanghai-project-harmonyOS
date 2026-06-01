# PC Accuracy Baseline Sync

This HarmonyOS version has been synced with the latest PC accuracy-improved
baseline.

## Ported capabilities

- Gemma4 4B wording and offline edge workflow are preserved.
- B-mode feature extraction now emits the PC-style 14-dimensional vector:
  mean, variance, horizontal and vertical differences, gradient, edge density,
  entropy, DoG mean/high response, chamber area proxy, speckle residual,
  contrast gain, directional anisotropy, and symmetry proxy.
- The study aggregator now reports both absolute `contractility_proxy` and
  relative `contractility_fraction_proxy` for systole/diastole pairs.
- The rule fallback uses the CAMUS-derived low-EF B-mode calibration from the
  PC version, plus motion-based contractility checks, before emitting
  `左心室收缩功能减低`.
- A4C/A2C view detection accepts common `4ch` and `2ch` filename labels.
- Supported extension declarations now include common cine/video containers
  alongside PNG/JPEG/TIFF/DICOM/DCOM. Actual decoding still depends on the
  HarmonyOS image/video decoder available on the target device.

## Compatibility note

The HarmonyOS build keeps the same input/output contract as the PC version:
multiple study files or frames in, one teaching reference diagnosis report out.
This is a medical teaching aid only and must not be used as clinical diagnosis,
treatment advice, or a doctor's order.
