# Study Hall — Full Project Outline (Phases 0–6)

---

## Phase 0 — Blocking Demo **[DONE]**

A self-contained build to validate that Screen Time blocking works on a real device.
No Firebase, no auth, no networking. See `OUTLINE_DEMO.md` for full detail.

**Files to create:**
- `AuthorizationManager.swift` — requests Screen Time permission
- `BlockingManager.swift` — applies and clears app shields
- Update `ContentView.swift` — picker + block + timer UI

**Done when:** apps are visibly shielded on a real iPhone and auto-unblock after 10 minutes.

---

## Phase 1 — App Skeleton + Auth *(current priority)*

### Step 1 — Add Firebase SPM Packages
- Add `FirebaseAuth` and `FirebaseFirestore` via Swift Package Manager

### Step 2 — Sign in with Apple
- Add the "Sign in with Apple" capability to the Xcode target
- Create `AuthViewModel.swift` (`ObservableObject`) — handles the Apple credential flow and signs into Firebase Auth
- On first sign-in, write a `users/{uid}` doc to Firestore with `displayName`, `photoURL`, and empty `stats`

### Step 3 — Navigation Shell
- Replace `ContentView` with a root router: unauthenticated → `LoginView`, authenticated → `MainTabView`
- `MainTabView`: tabs for Home, Groups, and Profile

### Step 4 — Profile Screen
- Display name, avatar, `focusMinutes`, `currentStreak` read from Firestore
- Sign-out button

---

## Phase 2 — Groups

### Step 1 — Create a Group
- `CreateGroupView`: name input → writes `groups/{groupId}` doc, generates a random `inviteCode`, sets `createdBy` and `memberUids: [currentUid]`

### Step 2 — Join a Group
- `JoinGroupView`: invite code input → query Firestore for matching group → append `currentUid` to `memberUids`

### Step 3 — Group List Screen
- `GroupsView`: Firestore listener on groups where `memberUids` contains `currentUid`
- Tap a group → `GroupDetailView`

### Step 4 — Group Detail / Member Roster
- Show group name, invite code (copyable), and list of member display names

---

## Phase 3 — Sessions Core

### Step 1 — Host Starts a Session
- "Start Study Hall" button in `GroupDetailView`
- Writes `groups/{groupId}/sessions/{sessionId}` with `status: "lobby"`, `hostUid`, `durationMin`, `startAt`, and `blocklistConfig`
- Add current user to `participants` map with `state: "focused"`

### Step 2 — Lobby Screen
- All group members see the lobby via a Firestore real-time listener
- Show who has joined, who hasn't
- Members join by writing themselves into `participants`

### Step 3 — Session Goes Active
- Host taps "Start" → updates `status` to `"active"` in Firestore
- Each member's app observes the status change → calls `BlockingManager.shared.block(selection:)` locally

### Step 4 — `DeviceActivityMonitor` Extension
- Add a new app extension target: DeviceActivity Monitor
- Configure it with its own entitlements (Family Controls)
- `intervalDidStart` / `intervalDidEnd` callbacks handle blocking/unblocking reliably even when the main app is killed
- Replace the `Task.sleep` demo timer with a `DeviceActivitySchedule`

### Step 5 — Timer UI + Auto-Unblock
- Countdown timer in `SessionView` driven by `startAt + durationMin`
- On session end (timer fires or host ends early): update Firestore `status: "ended"`, each device calls `BlockingManager.shared.clear()`

---

## Phase 4 — Social Presence

### Step 1 — Per-Member Live State
- Firestore listener in `SessionView` on the `participants` map
- Each user's state: `"focused"` | `"left"` | `"opened"`

### Step 2 — Detect "Left Early"
- When a user closes the app mid-session, write `state: "left"` to their participant doc
- Use `scenePhase` observation or `DeviceActivityMonitor` callbacks

### Step 3 — Detect "Opened Blocked App"
- `DeviceActivityMonitor.eventDidReachThreshold` fires when a blocked app is launched
- Write `state: "opened"` to Firestore from the extension

### Step 4 — Live Leaderboard / Shame Wall UI
- `SessionView` shows a live list of all participants and their current state
- Visual indicators: focused = green, left = yellow, opened = red

### Step 5 — Push Notifications via FCM
- Add `FirebaseMessaging` SPM package
- Request `UNUserNotificationCenter` permission on first launch
- Store `fcmTokens` array on the user doc
- Send push notifications for: session started, someone left early, someone opened a blocked app
- Use Firebase Cloud Functions (or client-triggered Firestore writes) to fan out FCM messages to group members

---

## Phase 5 — Stats & Retention

### Step 1 — Track Focus Minutes
- On session end, compute `durationMin` for each participant who stayed `"focused"` the whole session
- Write delta to `users/{uid}/stats.focusMinutes` using a Firestore increment

### Step 2 — Individual Streaks
- Record the last date each user completed a session
- Increment `currentStreak` if consecutive days; reset to 0 if a day is skipped

### Step 3 — Group Streak
- Group streak survives only if every member completed at least one session that day
- Track on the `groups/{groupId}` doc

### Step 4 — Leaderboard
- Weekly leaderboard view: query top `focusMinutes` among group members for the current week
- Store as a sub-collection or a denormalized field on the group doc

---

## Phase 6 — Differentiators (pick 1–2)

### Option A — Stakes / Penalty
- Opt-in at session creation: "Donate $X to [charity you dislike] if you bail"
- Integration with a payment API (Stripe or Benevity)
- Session end triggers charge if participant `state == "left"` or `"opened"`

### Option B — Scheduled Recurring Halls
- Host creates a recurring schedule (e.g., Mon/Wed/Fri 7pm)
- Store as a `schedule` sub-doc on the group
- Cloud Function fires at scheduled time → creates session doc, sends FCM push to group

### Option C — Co-op Badges
- Define badge criteria (e.g., "whole group completes 10 sessions together")
- Track badge progress on the group doc
- Display earned badges in `GroupDetailView`

---

## Known Constraints & Risks

1. **Blocking is bypassable** — users can delete the app or disable Screen Time in iOS Settings. Social pressure is the real enforcement mechanism.
2. **Family Controls entitlement is gated** — development works immediately; App Store distribution requires Apple approval (submit early at https://developer.apple.com/contact/request/family-controls-distribution).
3. **Blocking is per-device, not remote** — Firestore signals each phone; each phone enforces locally via `ManagedSettingsStore`.
4. **`DeviceActivityMonitor` extension is fiddly** — runs out-of-process, has its own entitlements, hard to debug. Budget extra time in Phase 3.
5. **Individual Apple Developer account** — no real team invites; both developers share uncle's Apple ID in Xcode. Upgrade to Organization account if the project gets serious.
6. **Android would be a near-total rewrite** — completely different APIs (UsageStats, Accessibility Services). Budget it as a separate project.
7. **Cold start problem** — a group social app is worthless with one user. Seed the first few groups deliberately with real friend groups.
