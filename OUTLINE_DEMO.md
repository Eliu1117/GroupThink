# Study Hall — Phase 0 Blocking Demo Outline

A self-contained build to validate that Screen Time blocking works on a real device.
No Firebase, no auth, no networking.

---

## Step 1 — Create `AuthorizationManager.swift`

- Singleton class (`static let shared`)
- `@MainActor`, `ObservableObject` with `@Published var isAuthorized: Bool`
- One async method: `requestAuthorization()` calls `AuthorizationCenter.shared.requestAuthorization(for: .individual)`
- Handle the authorized vs. denied state and publish it

## Step 2 — Create `BlockingManager.swift`

- Singleton class (`static let shared`)
- Holds a `ManagedSettingsStore` instance
- `func block(selection: FamilyActivitySelection)` — sets `store.shield.applications` and `store.shield.applicationCategories`
- `func clear()` — calls `store.clearAllSettings()`

## Step 3 — Replace `ContentView.swift`

- `@StateObject` for `AuthorizationManager`
- `@State` for `FamilyActivitySelection`, `showPicker: Bool`, `isBlocking: Bool`, `timeRemaining: Int`
- Button 1: "Request Screen Time Permission" → calls `AuthorizationManager.shared.requestAuthorization()`
- Button 2: "Choose Apps to Block" → sets `showPicker = true`, attached via `.familyActivityPicker(isPresented:selection:)`
- Button 3: "Start 10-Minute Block" → calls `BlockingManager.shared.block(selection:)`, kicks off a `Task` with `Task.sleep` for 600 seconds, then calls `clear()`
- Button 4: "Stop / Unblock Now" → calls `BlockingManager.shared.clear()`, cancels the timer task
- Display selected app count and a countdown timer while active

## Step 4 — Verify Entitlements

- Confirm `com.apple.developer.family-controls = true` is in the `.entitlements` file (already present)
- Confirm the capability is also enabled in the Xcode target's Signing & Capabilities tab

## Step 5 — Test on a Physical iPhone

- Build and run on a real device (Simulator will not work)
- Walk through the full flow: request permission → pick apps → start block → verify apps are shielded → wait for auto-unblock or hit Stop

---

## Important Caveats

- Family Controls APIs **do not work in the Simulator** — must use a physical iPhone
- The `Task.sleep` timer does **not** survive the app being killed — a `DeviceActivityMonitor` extension is needed for reliable background timing (addressed in Phase 3 of the full project)
- Do not add Firebase reads/writes, Sign in with Apple, or groups until this demo is confirmed working on device
