# Study Hall — Setup & Manual Steps

The full app code (Phases 0–5, plus a Phase 6 hook) is implemented. Because some
things can only be configured in Xcode's UI or the Firebase console, this file lists
the manual steps required to build and run.

Everything under `Screen time demo/` is auto-compiled into the app target (the project
uses Xcode 16 synchronized folders), so the new Swift files need no `.pbxproj` editing.

---

## 1. Code map

```
Screen time demo/
├── Screen_time_demoApp.swift     # @main, Firebase + notifications bootstrap
├── Models/                       # AppUser, StudyGroup, StudySession
├── Services/                     # UserService, GroupService, SessionService (Firestore)
├── Managers/
│   ├── AuthorizationManager.swift  # Screen Time permission
│   ├── BlockingManager.swift       # ManagedSettings shield + DeviceActivity schedule
│   ├── BlocklistStore.swift        # local FamilyActivitySelection (App Group)
│   ├── AccountManager.swift        # Sign in with Apple -> Firebase Auth
│   ├── NotificationManager.swift   # FCM + UNUserNotificationCenter
│   └── StudyHallShared.swift       # shared identifiers (store name, app group)
├── ViewModels/                   # GroupsVM, SessionVM, ProfileVM
├── Utilities/                    # chunking + day-key helpers
└── Views/                        # RootView, LoginView, MainTabView, Groups/, Session/, Blocking/, ProfileView

StudyHallMonitor/                 # DeviceActivityMonitor extension (separate target — see step 4)
firestore.rules                   # Firestore security rules
firebase.json                     # Firebase project config
functions/                        # Cloud Functions (FCM fanout)
```

---

## 2. Capabilities to enable in Xcode (Signing & Capabilities tab)

For the **Screen time demo** app target:

- **Family Controls** — already present (`Screen time demo.entitlements`).
- **App Groups** — add the group `group.com.davechengapps.screentimedemo`.
  (Already written into the entitlements file; confirm it shows checked in the UI so
  the provisioning profile picks it up.)
- **Sign in with Apple** — add this capability (required for Phase 1 auth).
- **Push Notifications** — add this capability (required for Phase 4 FCM).
- **Background Modes** → enable *Remote notifications* (for background FCM).

> The App Group id is referenced in code in `StudyHallShared.swift` and
> `BlocklistStore.swift`. If you change it, change it in both places **and** in the
> monitor extension's `Info.plist` / entitlements.

---

## 3. Firebase console

1. **Authentication** → enable the **Apple** sign-in provider.
2. **Firestore** → create the database, then deploy rules:
   ```bash
   firebase deploy --only firestore:rules
   ```
3. **Cloud Messaging** → upload your **APNs auth key (.p8)** under
   Project Settings → Cloud Messaging → Apple app configuration.
4. **Cloud Functions** (for push fanout):
   ```bash
   cd functions
   npm install
   cd ..
   firebase deploy --only functions
   ```

`GoogleService-Info.plist` is already in the project and is git-ignored — do not commit it.

---

## 4. DeviceActivityMonitor extension (Phase 3)

The reliable background timer needs a separate extension target. The source already
exists in `StudyHallMonitor/`; you just need to register the target:

1. **File → New → Target… → Device Activity Monitor Extension**. Name it
   `StudyHallMonitor`.
2. Delete the auto-generated source/Info.plist and instead add the files from the
   existing `StudyHallMonitor/` folder (`StudyHallMonitor.swift`, `Info.plist`,
   `StudyHallMonitor.entitlements`).
3. In the extension target's **Signing & Capabilities**, add **Family Controls** and
   the same **App Group** (`group.com.davechengapps.screentimedemo`).
4. Point the extension's `CODE_SIGN_ENTITLEMENTS` build setting at
   `StudyHallMonitor/StudyHallMonitor.entitlements`.

Until the extension exists, `BlockingManager.startScheduledSession` falls back to an
in-app shield (works while the app is alive, but won't survive a force-quit).

---

## 5. Run on a physical device

Family Controls APIs **do not work in the Simulator**. Build to a real iPhone that's
registered under the Apple Developer account. Then:

1. Sign in with Apple.
2. Profile tab → allow Screen Time access → choose apps to block → enable notifications.
3. Create a group, share the invite code with a second device.
4. Start a study hall; both devices block their own chosen apps and show live presence.

---

## 6. Build phases recap (what maps to what)

| Phase | Status | Where |
|-------|--------|-------|
| 0 — Blocking demo | done | `Views/Blocking/BlockingDemoView.swift`, `AuthorizationManager`, `BlockingManager` |
| 1 — Auth + skeleton | done | `AccountManager`, `LoginView`, `RootView`, `MainTabView`, `ProfileView` |
| 2 — Groups | done | `GroupService`, `GroupsViewModel`, `Views/Groups/*` |
| 3 — Sessions core | done | `SessionService`, `SessionViewModel`, `Views/Session/*`, `StudyHallMonitor/` |
| 4 — Social presence | done | participant states, `Cloud Functions`, `NotificationManager` |
| 5 — Stats & streaks | done | `UserService.recordCompletedSession`, Profile stats |
| 6 — Differentiators | hook | group streak field present; build one differentiator next |

---

## 7. Known limitations (carried over from AGENT_CONTEXT.md)

- Blocking is bypassable by design — social pressure is the real mechanism.
- Family Controls tokens are device-specific, so each member blocks their **own**
  chosen apps; the host's blocklist count is shown for context only.
- Distribution requires the gated Family Controls entitlement from Apple.
