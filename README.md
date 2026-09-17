# 🎙️ Voice Calculator

A professional voice-enabled calculator built with **Flutter**. Speak a calculation naturally — *"twenty five point five times four"*, *"square root of eighty one"*, *"20 percent of 150"* — and get the result instantly. Includes a full scientific engine, calculator key sounds, history, and a responsive Material 3 UI in cornflower & ice blue.

## 📲 Try it

| | |
|---|---|
| **🌐 Web demo** (open on any PC/Chrome): | <https://abinaya-devops.github.io/voice_calculator/> |
| **📱 Android app** (install the APK): | <https://github.com/abinaya-devops/voice_calculator/releases/tag/latest> |

**Scan with a phone camera** — left: open the web demo · right: download the Android APK

| Web demo | Android APK |
|---|---|
| ![](docs/qr-web.png) | ![](docs/qr-apk.png) |

> **Installing the APK:** after downloading, Android may ask to "allow installs from this source" and Play Protect may offer a security scan — both are normal one-time steps for apps shared outside the Play Store.

## ✨ Features

**Voice recognition**
- Natural speech: compound numbers (*"two thousand five hundred"* → 2500), decimals (*"three point five"* → 3.5), and operators (*"divided by"*, *"into"*, *"upon"*, *"to the power of"*)
- Dictated expressions like `8/7/2/3+6+3/4` are recognized correctly
- Scientific commands: *"square root of 81"*, *"5 factorial"*, *"sin 30"*, *"log of 100"*
- Voice commands: *"clear"*, *"delete"*
- Live transcript with "Heard …" confirmation, and a big centered mic button with calm ripple rings (fixed footprint — no layout shake)

**Correct calculations**
- Proper operator precedence, parentheses, unary minus, implicit multiplication (`2(3+4)`, `2π`)
- Real-calculator percent semantics: `200+10%` → 220, `200−10%` → 180, `50%` → 0.5
- Scientific: sin/cos/tan (DEG/RAD toggle), asin/acos/atan, ln/log, √, x², x³, n!, mod, 1/x, π, e, ANS
- Auto-closes unclosed parentheses, clean output (no `0.30000000000000004`)

**Experience**
- Saira typeface, cornflower/ice-blue palette, light & dark themes (persisted)
- Calculator-style key sounds (toggleable), haptic feedback
- History with persistence, per-item delete, and one-tap reuse
- Copy & share results
- Responsive: phone portrait, tablet/landscape side-by-side layout

## 🚀 Getting started

```bash
flutter pub get
flutter run
```

> The microphone requires a real device (Android/iOS) or a Chromium-based browser. Android emulators may lack a speech-recognition service.

### Run the tests

```bash
flutter test
```

## 🌐 Web demo

Every push to `master` runs the GitHub Actions workflow (`.github/workflows/deploy-web.yml`): tests run, the web app builds, and it deploys to **GitHub Pages**. Enable it once in your repo: **Settings → Pages → Source: GitHub Actions**.

## 🛠️ Regenerating assets

The logo PNGs and key-sound WAVs are generated from code:

```bash
flutter test tool/generate_assets_test.dart   # renders logo + sounds
dart run flutter_launcher_icons               # applies launcher icons
```

## 📁 Project structure

```
lib/
├── main.dart                    # UI, theme, keypad, voice flow
├── core/
│   ├── expression_engine.dart   # tokenizer + recursive-descent parser
│   ├── voice_parser.dart        # speech → math expression
│   └── key_sounds.dart          # key-press sounds
└── widgets/
    └── app_logo.dart            # canvas-drawn logo
```

## 👤 Author

**Abinaya M**
