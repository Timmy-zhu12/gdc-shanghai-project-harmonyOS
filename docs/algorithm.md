# CardioConsult HarmonyOS algorithm notes

This HarmonyOS version keeps the same edge-computing workflow as the PC prototype:

1. Load multiple PNG/JPG/BMP/TIFF or DICOM/DCOM files selected by the user.
2. Split supported DICOM cine files into frames.
3. Normalize every frame to a 256 x 256 RGB matrix.
4. Infer standard cardiac ultrasound view labels from file names when available.
5. Infer systole/diastole from file names first, then use chamber-area proxy within each view.
6. Extract B-mode structural features from robustly normalized grayscale images.
7. Convert Color Doppler pixels into an HSV-derived simplified flow vector field.
8. Aggregate per-frame features into a study-level summary.
9. Build a Gemma4 4B prompt and try the offline native backend.
10. If the native backend is unavailable, use deterministic local teaching rules.

## B-mode features

The B-mode path computes:

- grayscale mean and variance
- horizontal and vertical difference means
- gradient magnitude proxy
- edge-density proxy
- normalized texture entropy
- Difference-of-Gaussians-like enhancement using two local blurs
- high-response DoG ratio
- chamber-area proxy

The chamber-area proxy is used to classify phases when file names do not contain `ED`, `ES`, `diastole`, `systole`, `舒张`, or `收缩`.

## Color Doppler features

The Doppler path maps RGB to HSV and uses:

```text
speed = saturation * value
theta = hue_to_theta(hue)
vx = speed * cos(theta)
vy = speed * sin(theta)
```

It then aggregates:

- flow direction ratio
- mean speed proxy
- active flow area ratio
- turbulence proxy
- gradient energy
- divergence proxy
- vorticity proxy

These are teaching proxies, not calibrated hemodynamic measurements. Real velocity scale, Nyquist limit, gain, probe angle, aliasing, and DICOM calibration tags are not fully modeled.

## Teaching diagnosis labels

The fallback rule engine intentionally emits concrete teaching labels, including:

- mild or moderate mitral regurgitation
- mild or moderate tricuspid regurgitation
- mild aortic regurgitation
- mild aortic stenosis tendency
- mild pulmonary regurgitation
- left ventricular systolic dysfunction
- segmental wall motion abnormality
- insufficient evidence, no clear abnormality tendency
- no clear echocardiographic abnormality

All outputs are for medical teaching and competition demonstration only.
