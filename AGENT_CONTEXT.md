# Study Hall App — Agent Context File

This file is the single source of truth for a new agent joining this project.
Read it fully before making any changes.

---

## What this app is

A native iOS **group study hall** app. Friends download the app, someone starts a
"study hall" for a set duration, and each member's phone blocks a customizable list
of distracting apps for the duration. The key social twist: everyone in the group
can see who stayed focused, who left early, or who opened a blocked app.

**The product's real value is social accountability, not technical lockdown.**
A determined user can always delete the app or toggle off Screen Time in Settings.
That is expected and fine — the design leans into peer pressure, not hard enforcement.

---

## Current project state

The Xcode project is located at:
`~/Desktop/Screen time demo/`

### Existing files

```
Screen time demo/
├── Screen time demo.xcodeproj
├── Screen time demo/
│   ├── Screen_time_demoApp.swift   # @main entry — Firebase already configured
│   ├── ContentView.swift           # Placeholder only ("Hello world")
│   ├── Screen time demo.entitlements  # Family Controls entitlement already added
│   ├── GoogleService-Info.plist    # Firebase project config (do NOT commit to public repo)
│   └── Assets.xcassets
├── Screen time demoTests/
└── Screen time demoUITests/
```

### What is already done

- Xcode project created, iOS 16+ deployment target
- **Family Controls** entitlement present (`com.apple.developer.family-controls = true`)
- **Firebase** integrated via Swift Package Manager (`FirebaseCore` imported, `FirebaseApp.configure()` called in `AppDelegate`)
- `GoogleService-Info.plist` present (Firebase project connected)
- Signed with uncle's Apple Developer Individual account

### What is NOT done yet

- `ContentView.swift` is a blank placeholder — no real UI exists
- No `AuthorizationManager` (Screen Time permission)
- No `BlockingManager` (ManagedSettings shield)
- No `FamilyActivityPicker` integration
- No session timer
- No Firebase Auth / Sign in with Apple
- No Firestore reads/writes
- No groups, sessions, friends, presence, or notifications
- No `DeviceActivityMonitor` extension

---

## Tech stack

| Layer | Choice | Notes |
|-------|--------|-------|
| UI | SwiftUI | iOS 16+ only, no UIKit |
| App blocking | FamilyControls + ManagedSettings + DeviceActivity | Apple frameworks, device-local only |
| Backend | Firebase (Firestore + Auth + FCM) | Already integrated via SPM |
| Auth | Sign in with Apple via Firebase Auth | Not yet implemented |
| Push | Firebase Cloud Messaging (FCM) | Not yet implemented |
| Server logic | Firebase Cloud Functions (optional, later) | Not yet implemented |

### Firebase SPM packages needed (add as needed per phase)

- `FirebaseCore` — already present
- `FirebaseAuth` — needed Phase 1
- `FirebaseFirestore` — needed Phase 1
- `FirebaseMessaging` — needed Phase 4

### Apple frameworks (no SPM, import in code)

- `FamilyControls` — Screen Time authorization + picker
- `ManagedSettings` — apply/remove app shields
- `DeviceActivity` — schedule session timing in extension
- `UserNotifications` — local notification permission

---

## Architecture

Blocking is **on-device and local**. The host does not remotely control anyone's phone.
Firestore broadcasts session state; each member's local app reacts to that state and
applies the same blocklist to its own device via `ManagedSettingsStore`.

```
Each member's iPhone:
  SwiftUI App
    ├── AuthorizationManager   (Screen Time permission)
    ├── BlockingManager        (ManagedSettingsStore — applies shield)
    ├── SessionViewModel       (reads Firestore session, drives blocking)
    └── DeviceActivityMonitor  (app extension — reliable background timer)

Firebase (cloud):
  ├── Auth                     (Sign in with Apple)
  ├── Firestore                (groups, sessions, presence)
  ├── Cloud Messaging          (push notifications)
  └── Cloud Functions          (optional server-side session lifecycle)
```

---

## Firestore data model

```
users/{uid}
  displayName: String
  photoURL: String?
  fcmTokens: [String]
  stats:
    focusMinutes: Int
    currentStreak: Int

groups/{groupId}
  name: String
  memberUids: [String]
  inviteCode: String
  createdBy: String (uid)

groups/{groupId}/sessions/{sessionId}
  hostUid: String
  startAt: Timestamp
  durationMin: Int
  status: "lobby" | "active" | "ended"
  blocklistConfig: { applicationTokens, categoryTokens }
  participants:
    {uid}:
      state: "focused" | "left" | "opened"
      joinedAt: Timestamp
```

Presence is updated per-session as members join, leave early, or open a blocked app.

---

## Build phases

### Phase 0 — Blocking demo (current priority)

Goal: on a real iPhone, pick apps, block them, unblock after 10 minutes.
No Firebase, no auth, no groups. Just validate that blocking works.

Files to create:
- `AuthorizationManager.swift` — requests `AuthorizationCenter` Screen Time permission
- `BlockingManager.swift` — wraps `ManagedSettingsStore` to apply/clear shields
- Update `ContentView.swift` — buttons: Request permission, Choose apps, Start 10 min, Stop

Key code patterns:

```swift
// Authorization
try await AuthorizationCenter.shared.requestAuthorization(for: .individual)

// Picker (in SwiftUI view)
@State private var selection = FamilyActivitySelection()
.familyActivityPicker(isPresented: $showPicker, selection: $selection)

// Block
store.shield.applications = selection.applicationTokens
store.shield.applicationCategories = .specific(selection.categoryTokens)

// Unblock
store.clearAllSettings()

// Demo timer (simple, app must stay alive)
Task {
    try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
    BlockingManager.shared.clear()
}
```

Important caveats:
- Family Controls APIs **do not work in the Simulator** — must use a physical iPhone
- App blocking is **always on-device** — there is no remote control of another phone
- The in-app `Task.sleep` timer does not survive the app being killed — a `DeviceActivityMonitor`
  extension is required for reliable background timing (Phase 3)

### Phase 1 — App skeleton + auth

- Sign in with Apple via Firebase Auth
- Write user doc to Firestore on first sign-in
- Basic navigation shell (tab bar or NavigationStack)
- User profile screen

### Phase 2 — Groups

- Create a group (generate invite code)
- Join a group via invite code
- Group list screen
- Member roster

### Phase 3 — Sessions core

- Host starts session: writes session doc to Firestore, status = "lobby"
- Members join lobby, all see who's in
- When host starts: status = "active", each member's app applies local blocking
- `DeviceActivityMonitor` extension handles session end reliably in background
- Timer countdown UI
- Auto-unblock when timer ends or host ends early

### Phase 4 — Social presence

- Live per-member state: focused / left / opened blocked app
- Firestore listener updates all participants in real time
- Push notifications via FCM ("Alex started a study hall", "Jordan left early")
- "Left early" and "opened app" events visible to whole group

### Phase 5 — Stats & retention

- Focus minutes tracked per session per user
- Individual streaks (days studied)
- Group streak (all members studied = streak survives)
- Leaderboard (weekly focus minutes)

### Phase 6 — Differentiators (pick 1–2)

- Stakes/penalties (opt-in: donate to charity you hate if you bail)
- Scheduled recurring halls (Mon/Wed/Fri 7pm, auto-ping group)
- Co-op rewards (group unlocks cosmetics/badges together)

---

## Developer setup

- **Apple Developer account**: uncle's Individual plan ($99/yr, one person)
- **Both developers** sign into Xcode using uncle's Apple ID (Individual plan does not
  support real team invites — shared account is the workaround)
- **Both iPhones** must be registered under uncle's account in the developer portal
  (Certificates, Identifiers & Profiles → Devices)
- **Firebase**: add both developers as Editors in the Firebase console (free)
- **Git**: use a private repo; never commit `GoogleService-Info.plist` or `.p12` files

### Distribution entitlement (needed before TestFlight/App Store)

The development Family Controls entitlement works immediately.
For distribution, submit a separate request to Apple:
https://developer.apple.com/contact/request/family-controls-distribution

This requires Apple approval and can take time — submit early.

---

## Known constraints and honest risks

1. **Blocking is bypassable** — users can delete the app or disable Screen Time in
   iOS Settings. The product's real enforcement mechanism is social pressure, not
   technical lockdown. Never market it as "unbreakable."

2. **Family Controls entitlement is gated** — distribution requires Apple approval.
   Development works immediately; App Store does not.

3. **Blocking is per-device, not remote** — the host cannot lock anyone else's phone
   from the server. Firestore tells each phone "session is active"; each phone enforces
   locally. This is Apple's design, not a workaround.

4. **DeviceActivityMonitor extension is fiddly** — it runs out-of-process, has its own
   entitlements, and is hard to debug. Budget extra time in Phase 3.

5. **Individual Apple Developer account** — no real team invites. Both developers share
   uncle's Apple ID in Xcode. If the project gets serious, upgrade to an Organization
   account ($99/yr, requires D-U-N-S number and legal entity).

6. **Android would be a near-total rewrite** — Android has completely different APIs
   (UsageStats, Accessibility Services). Budget it as a separate project.

7. **Cold start problem** — a group social app is worthless with one user. Seed the first
   few groups deliberately with real friend groups.

---

## File naming and code conventions

- SwiftUI only, no UIKit (except where unavoidable, wrapped in `UIViewRepresentable`)
- Use `@MainActor` on classes that update UI
- Use `ObservableObject` + `@Published` for ViewModels
- `BlockingManager` and `AuthorizationManager` are singletons (`static let shared`)
- Do not import Firebase into the `DeviceActivityMonitor` extension target
- Keep Firestore security rules strict: users can only read/write their own data
  and sessions they are participants in

---

### Firestore Schema Updates for Phase 4
* **Path:** `/sessions/{sessionId}`
* **Field:** `participants` (Map)
    * Key: `userId` (String)
    * Value: `Object` containing:
        * `name`: String
        * `status`: String (`"focused"` | `"left"` | `"opened"`)
        * `lastUpdated`: Timestamp

### Device Activity & Shield Callbacks
* **App Backgrounding (Detect "Left Early"):** Use SwiftUI's `scenePhase` tracking in the main application to catch `.background` transitions and update the user's Firestore status to `"left"`.
* **Shield Bystander (Detect "Opened Blocked App"):** The `DeviceActivityMonitor` extension (`StudyHallMonitor`) must override `intervalDidReachThreshold`. When triggered, it should perform a direct Firestore write or invoke a lightweight background network task to set the member's status to `"opened"`.

## Where things stand right now
* **Completed:** Phase 0, 1, 2, and 3. Screen Time shielding, Firebase Auth, Group creation/deletion, and Session synchronization (`SessionService`, `GroupService`) are fully implemented and verified on physical devices.
* **Current Target:** Phase 4 (Social Presence).
* **Shared Infrastructure:** Use the existing App Group identifier (`group.com.davechengapps.screentimedemo`) to share Firestore session state or configurations between the main app targets and the `StudyHallMonitor` device activity extension.

### Phase 4 UI Requirements
* **Leaderboard Row component:** Displays participant name and an status indicator dot.
* **Color Mapping:**
    * `"focused"` -> `.green`
    * `"left"` -> `.yellow`
    * `"opened"` -> `.red`