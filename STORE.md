# GyroWheel — App Store / publishing kit

Ready-to-paste ASO copy, monetization plan, and submission notes for the iOS app
and the macOS receiver. Char limits are App Store Connect maximums.

---

## 0. Publishing reality (read first)

- **iOS app** — publishable, but it's a *companion app* (useless without the Mac
  receiver running). Reviewers must be able to see it work. Mitigate with:
  - A built-in **Demo/Test mode** (wheel reacts to tilt with no Mac connected).
  - **Review notes** linking a notarized download of the Mac receiver + 3-step setup.
- **macOS receiver** — needs the `com.apple.developer.hid.virtual.device`
  entitlement, which Apple restricts to "virtualization software." App Store
  approval is uncertain. **Recommended: ship the Mac app FREE via Developer ID +
  notarization (direct download)**, not the App Store. Do not ship the SIP/AMFI-off
  build — that can't run on a normal user's Mac.
- **Net plan:** monetize the **iPhone** app (free + Pro IAP); keep the **Mac** app
  free (it's the enabler — charging both halves doubles friction).

---

## 1. Monetization

- Model: **Free + one non-consumable "GyroWheel Pro" unlock, $3.99** (one-time).
- Optional: a **"Tip the developer"** consumable ($0.99 / $2.99 / $4.99).
- No ads. No subscription. Not paid-upfront.
- Free vs Pro split:
  - **Free:** tilt steering, throttle/brake, up to **4** buttons, 1 layout,
    default theme, auto-discovery, calibration.
  - **Pro:** **5–8 buttons**, **saved layout profiles** (per game), **color
    themes / appearance**, **Toggle/Tap** button modes, advanced steering tuning.
- StoreKit 2 implementation is straightforward; gate the Pro features behind a
  single `isPro` flag. (Ask and I'll wire it up + a restore-purchases button.)

---

## 2. iOS app — store listing

**App Name (≤30):**
`GyroWheel: Motion Racing Wheel`
_(alt: `GyroWheel – Racing Wheel`)_

**Subtitle (≤30):**
`Tilt-to-steer wheel & gamepad`

**Keywords (≤100, comma-separated, NO spaces, NO trademarks):**
`racing,wheel,gamepad,controller,sim,steering,gyroscope,motion,driving,tilt,joystick,remote,pedal`

**Promotional text (≤170):**
`Turn your iPhone into a motion steering wheel for driving games on your Mac — tilt to steer, analog throttle & brake, custom buttons. Auto-connects over Wi-Fi.`

**Description (≤4000):**
```
Turn your iPhone into a gyroscope steering wheel for your Mac.

Tilt your phone to steer, slide for analog throttle and brake, and tap fully
customizable on-screen buttons. GyroWheel streams your motion to a free
companion app on your Mac over Wi-Fi with very low latency, where it appears as
a standard game controller — great for racing and driving games and emulators.

HOW IT WORKS
1. Install the free GyroWheel receiver on your Mac.
2. Open GyroWheel on your iPhone — it finds your Mac automatically (Bonjour).
3. Hold the phone like a wheel and drive.

FEATURES
• Gyroscope steering with adjustable sensitivity, deadzone, smoothing and a
  response curve for fine control near center
• Analog throttle and brake on a spring-back slider
• Auto-invert when you flip the phone around
• Calibrate-on-launch so center is always right
• Customizable buttons — label, color, size, position, and behavior
  (Hold / Toggle / Tap)
• Drag-to-arrange layout: place the wheel, pedals, and buttons anywhere
• Appearance options: themes, colors, button shapes, opacity
• Automatic Wi-Fi discovery of your Mac — no IP typing
• Landscape, full-screen, screen-stays-awake driving HUD

GyroWheel PRO (one-time unlock)
• Up to 8 buttons
• Saved layout profiles per game
• Color themes and full appearance control
• Toggle/Tap button modes and advanced tuning

REQUIRES the free GyroWheel Mac receiver (download link in the app and at
<your-site>). iPhone and Mac must be on the same Wi-Fi network.
```

**What's New (first release):**
`First release: motion steering, analog pedals, custom buttons, drag-to-arrange
layout, and automatic Wi-Fi discovery of your Mac.`

**Primary category:** Utilities  ·  **Secondary:** Sports (or Entertainment)
_(Avoid "Games" — non-games can be rejected there.)_

---

## 3. macOS receiver — listing (if distributed; else use for the download page)

**App Name (≤30):** `GyroWheel Receiver`
**Subtitle (≤30):** `Phone-powered virtual gamepad`
**Keywords (≤100):**
`gamepad,controller,virtual,joystick,racing,wheel,input,driver,phone,bridge`
**Promo (≤170):**
`Receives your iPhone's GyroWheel motion and presents it to macOS as a standard
game controller — analog steering, throttle, brake, and buttons.`
**Category:** Utilities

---

## 4. Trademark safety (avoids rejection / removal)

Do **NOT** put these in the name, subtitle, or keyword field:
`Xbox, PlayStation, Nintendo, Switch, Forza, F1, Gran Turismo, Minecraft,
CrossOver, Whisky, Wine, Steam`.
You may describe compatibility *generically* in the long description
("works with games that accept a standard controller", "racing and driving
games and emulators"). Don't claim endorsement.

---

## 5. Screenshots (6.7" + 6.5" iPhone, 12.9" iPad, plus Mac)

1. The driving HUD in action (wheel rotated, pedals lit) — caption: "Tilt to steer."
2. Layout edit mode (dragging buttons) — "Make it yours."
3. Settings/appearance — "Themes, buttons, tuning."
4. Auto-discovery chip — "Finds your Mac automatically."
5. Pro features — "Up to 8 buttons + saved profiles."
Add a 15–30s App Preview video of real driving if possible (huge for conversion).

---

## 6. Pre-submission checklist

- [ ] Build a reviewer **Demo/Test mode** (works with no Mac).
- [ ] Review notes: link the notarized Mac receiver + setup steps + a test video.
- [ ] Privacy "nutrition label": no data collected (it's all local). Add
      `NSLocalNetworkUsageDescription` / `NSMotionUsageDescription` (already set).
- [ ] Support URL + marketing URL (a simple landing page with the Mac download).
- [ ] App Privacy: confirm "Data Not Collected."
- [ ] Price tier for the Pro IAP; localize at least the keywords for big markets.
