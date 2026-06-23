# GyroWheel

A landscape SwiftUI iOS app that turns an iPhone into a gyroscope steering wheel
with a spring-back throttle/brake and 4 macro buttons. The phone streams a 60 Hz
`InputPacket` over UDP to a macOS receiver. Pick the receiver that fits:

| | Receiver | Analog? | What it needs |
|---|---|---|---|
| **A** | `mac/receiver.py` — keyboard / mouse | no (digital/PWM) | just Accessibility; any account |
| **C** | `mac/VirtualHID/` — userspace virtual gamepad (`IOHIDUserDevice`) | **yes** | the virtual-HID entitlement **or** SIP+AMFI off (personal use) |
| **B** | `mac/VirtualGamepad/` — DriverKit system extension | **yes** | paid account + Apple-approved DriverKit/HID entitlements |

**For a real analog gamepad with the least hassle, use C.** It's a single signed
CLI — no DriverKit, no system extension, no embedding. With a paid account you can
sign it with the granted entitlement; for purely personal use you can disable SIP
+ AMFI so the ad-hoc entitlement is honored.

```
iPhone (CoreMotion + Network.framework, 60 Hz UDP, InputPacket JSON)
        │
        ▼
  macOS receiver ──▶  A: synthesized keyboard / mouse        (pynput)
                 ├──▶  C: IOHIDUserDevice virtual gamepad     (analog, userspace)
                 └──▶  B: DriverKit HID system extension      (analog, distributable)
```

> **Why not GCVirtualController / WiiController's VirtualController?**
> `GCVirtualController` isn't in the macOS SDK and is in-process only.
> WiiController/VirtualController is itself a DriverKit system extension you build
> & sign yourself (same as B, no prebuilt signed release). Creating an analog
> virtual controller always needs a virtual-HID entitlement — which C satisfies
> the cheapest way (entitlement *or* SIP/AMFI off).

## Layout

```
GyroWheel/
├── ios/                         # iPhone app (see "iOS app" below)
│   ├── project.yml  setup.sh    # XcodeGen spec + one-command project setup
│   └── *.swift  Assets.xcassets
├── mac/
│   ├── receiver.py  requirements.txt   # A) keyboard / mouse (pynput)
│   ├── Receiver/                       # C-app) simple desktop receiver (GUI, RECOMMENDED)
│   │   ├── Sources/                    #    SwiftUI app · IOHIDUserDevice · UDP · onboarding
│   │   ├── project.yml  build.sh       #    build (ad-hoc signed) + launch
│   │   └── Receiver.entitlements
│   ├── VirtualHID/                     # C-cli) same engine, terminal version
│   │   ├── main.swift  bridge.h  build.sh
│   │   └── VirtualHID.entitlements
│   └── VirtualGamepad/                 # B) DriverKit system extension (distributable)
│       ├── Shared/  Driver/  Host/     #    shared header · .dext · host .app
│       ├── project.yml  setup.sh  build_driver_check.sh
└── tools/gen_icon.swift               # regenerates the iOS app icon
```

The wire packet (iOS → Mac), matching `InputPacket` on both sides:

```json
{ "steer": -1.0..1.0, "throttle": 0.0..1.0, "brake": 0.0..1.0,
  "buttons": { "btn1": false, "...": false, "btn8": false } }
```
(Up to 8 buttons; all three receivers map `btn1`…`btn8` to gamepad buttons / keys.)

---

## macOS receiver A — keyboard / mouse (default, works today)

```bash
cd GyroWheel/mac
python3 -m venv .venv && source .venv/bin/activate    # optional
pip3 install -r requirements.txt                      # pynput
python3 receiver.py
```

Grant **Accessibility** to your terminal (or Python) under **System Settings →
Privacy & Security → Accessibility**, or key presses are silently dropped. The
script prints the IP to enter on the phone and a live `Hz` readout.

Tune the `CONFIG` dict at the top of `receiver.py`:
- `steer_mode`: `"keyboard"` (proportional A/D via ~20 Hz PWM) or `"mouse"`
  (relative-mouse steering).
- `analog_pedals`: `True` to PWM (feather) throttle/brake instead of threshold hold.
- key maps for steering, pedals, and `btn1`…`btn4`.

This needs no Apple Developer account. It is digital-ish (PWM/relative), so it's
a weaker fit for a hardcore sim than analog — for that, use receiver C or B.

---

## macOS receiver C — userspace virtual gamepad (recommended for analog)

Publishes a real HID gamepad via `IOHIDUserDevice` — no DriverKit, no system
extension. True analog axes. Comes in two forms, same engine:

**Desktop app (simplest):** a small window that shows the IP to type on your
phone, live Hz, Start/Stop, and a first-launch setup guide.
```bash
cd GyroWheel/mac/Receiver
./build.sh          # builds + ad-hoc signs + launches GyroWheelReceiver.app
```

**CLI:** a single signed binary.

```bash
cd GyroWheel/mac/VirtualHID
./build.sh                 # compiles + ad-hoc signs ./gyrohid (prints run modes)
```

Creating a virtual HID device requires the `com.apple.developer.hid.virtual.device`
entitlement to be *honored*. Two ways:

**Mode B — paid account (no system changes).** Request the entitlement for your
account, then sign with your Developer ID and run normally:
```bash
SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh
./gyrohid
```

**Mode A — personal use, no Apple approval (your research path).** Disable the
checks that reject an ad-hoc entitlement. One-time, in **macOS Recovery**
(Apple Silicon: hold the power button → *Options* → Terminal):
```bash
csrutil disable
nvram boot-args="amfi_get_out_of_my_way=1"   # APPEND to any existing boot-args
```
Reboot, then `sudo ./gyrohid`. Re-enable later with `csrutil enable` (and clear
`boot-args` in Recovery).
> ⚠️ Disabling SIP + AMFI lowers security **machine-wide**, not just for this app.
> It's reversible, but only do it knowingly. If that's not acceptable, use Mode B
> (paid account) or receiver A.

Either way: run `gyrohid`, point the phone at this Mac's IP + port 5005, and it
appears as *GyroWheel Virtual Gamepad*. In F1 25 bind steer → X, throttle → Z,
brake → Rz.

---

## macOS receiver B — DriverKit virtual gamepad (advanced, true analog)

Needs a **paid Apple Developer account**. The project is generated for you and
is fully build-validated (iig + compile + the dext embeds into the app at
`Contents/Library/SystemExtensions/`); you only set your Team and approve the
extension.

### 1. Generate & open the project
```bash
cd GyroWheel/mac/VirtualGamepad
./setup.sh            # installs XcodeGen if needed, generates the project, opens Xcode
```
(Compile the driver standalone any time with `./build_driver_check.sh`.)

### 2. Request the managed entitlements (do this first — approval can take days)
The DriverKit + HID entitlements are "managed": request them once at
<https://developer.apple.com/contact/request/system-extension/> — ask for
**DriverKit**, **DriverKit Transport: HID**, and **DriverKit Family: HID**.
Until approved, Xcode signing will reject those entitlements. App IDs (auto-created
by Xcode automatic signing):
- Host:   `com.gyrowheel.VirtualGamepad`        (System Extension)
- Driver: `com.gyrowheel.VirtualGamepad.Driver` (DriverKit + HID)

### 3. Sign
In Xcode, for **both** the `GamepadReceiver` and `VirtualGamepadDriver` targets:
Signing & Capabilities → **Automatically manage signing** → your **Team**.

### 4. Allow local extensions & run
```bash
systemextensionsctl developer on        # lets a locally-built dext load; reboot after
```
- Press **⌘R** to launch GamepadReceiver.
- Click **Install / Activate**, then approve in
  **System Settings → General → Login Items & Extensions → Driver Extensions**.
- Status dot turns green → click **Start** (UDP `5005`).

### 5. Verify
Any gamepad tester shows *GyroWheel Virtual Gamepad*. In F1 25 (under
CrossOver/Whisky) bind steer → X axis, throttle → Z, brake → Rz.

---

## iOS app — deploy to your iPhone

```bash
cd GyroWheel/ios
./setup.sh
```

Installs XcodeGen (via Homebrew if missing), generates `GyroWheel.xcodeproj`,
and opens it. Then in Xcode (one time):

1. **GyroWheel** target → **Signing & Capabilities** → tick **Automatically
   manage signing** → choose your **Team**.
2. Plug in your iPhone, pick it in the device dropdown, press **⌘R**.
3. First launch only: iPhone → **Settings → General → VPN & Device Management →**
   trust your developer certificate, then reopen the app.

Build to a **physical device** — the gyro is unavailable in the Simulator.
Requires iOS 16+. Free Apple ID signing expires after 7 days (just re-run ⌘R).

---

## Using it

1. Phone and Mac on the **same Wi-Fi/LAN**.
2. Start a receiver on the Mac:
   - **C (analog, recommended):** `cd Receiver && ./build.sh` (a window shows the IP).
   - **A (keyboard/mouse):** `python3 receiver.py`.
   - **B (DriverKit):** launch **GamepadReceiver** → Install/Activate → Start.
3. **Auto-discovery (no IP typing):** every receiver advertises over **Bonjour**.
   The phone shows nearby Macs as green chips (top bar) and in the welcome flow /
   Settings — tap one to connect. Manual IP entry still works as a fallback.
4. Hold the phone like a wheel, **Connect** (auto-calibrates on launch by default).
5. Tilt to steer, slide for throttle/brake, tap macros.

### iOS tuning & layout (⚙️ Settings)
- **Steering:** Sensitivity · Full-lock angle · Deadzone · Smoothing · Response
  curve · Invert · **Auto-invert when flipped** · Calibrate on launch.
- **Buttons:** 2–8, each with label, color, behavior (Hold/Toggle/Tap), and size.
- **Edit layout on screen:** tap the slider icon (top bar), then **drag** the
  wheel, pedals, and buttons anywhere. "Reset layout" restores defaults.
- **Appearance:** background (black/gradient) · accent & throttle/brake colors ·
  button shape (circle/rounded) · control opacity · show/hide angle readout.
- **Pedals/feedback:** swap throttle↔brake · haptics · haptic on connect.

### Verified in this repo
- iOS app: builds clean for the iOS SDK; packet round-trips through the exact
  `InputPacket` decoder.
- macOS receiver A: `receiver.py` byte-compiles; decodes the live packet.
- macOS receiver C: both the `Receiver` desktop app and the `gyrohid` CLI build
  against the real `IOHIDUserDevice` API; the CLI embeds the entitlement in its
  signature.
- macOS receiver B: the generated Xcode project **builds end-to-end** with
  `CODE_SIGNING_ALLOWED=NO` — `iig` runs, both targets compile (arm64 + x86_64),
  and the dext embeds at `…app/Contents/Library/SystemExtensions/`.
- Not verifiable here (needs your machine state): the runtime device creation
  (entitlement honored / SIP+AMFI off), and the in-game controller binding.
