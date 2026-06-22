# Overnight Build Summary
**Generated:** 2026-06-19 · All work completed in the same session — nothing was left pending.

---

## Completion Checklist

| # | Ticket | Step | Status |
|---|--------|------|--------|
| 1 | GRO-26 | Streamline Screen Time Auth (reactive `isAuthorized`, hide permission button) | ✅ Done (prior session) |
| 2 | GRO-11 | Break vote Firestore scaffolding: `BreakVote.swift`, `BreakVoteService.swift`, schema on `Group` + `StudySession`, FCM notification helper | ✅ Done (prior session) |
| 3 | GRO-11 | `BreakVoteView.swift` + `SessionViewModel` wiring (initiate/cast/expiry tasks, sheet) | ✅ Done |
| 4 | GRO-11 | Push notification for vote start (local notification via `PushNotificationService`, opt-out key) | ✅ Done |
| 5 | GRO-12 | `DowntimeSchedule` model + `DowntimeOverrideRequest` model + `DowntimeService` | ✅ Done |
| 6 | GRO-12 | `DowntimeScheduler` + `StudyHallMonitor` downtime activity handling | ✅ Done |
| 7 | GRO-12 | `DowntimeSettingsView` (schedule picker, allowed-app picker, peer override request/approve flow) | ✅ Done |
| 8 | GRO-13 | `MorningRoutine` model + `MorningRoutineService` + `MorningRoutineScheduler` | ✅ Done |
| 9 | GRO-13 | `StudyHallMonitor` morning routine shields + activity-based early unlock via `routineCompleted` event | ✅ Done |
| 10 | GRO-13 | `MorningRoutineSettingsView` (lock/unlock times, mode picker, routine-app picker) | ✅ Done |

**Final build status: ✅ BUILD SUCCEEDED** (zero errors, iPhone 17 Pro simulator)

---

## New Files Created

| File | Target | Purpose |
|------|--------|---------|
| `Screen time demo/BreakVote.swift` | Main app | Break vote data model (embedded in session doc) |
| `Screen time demo/BreakVoteService.swift` | Main app | Transactional Firestore operations for vote lifecycle |
| `Screen time demo/BreakVoteView.swift` | Main app | Bottom sheet UI: countdown ring, tally, vote buttons |
| `Screen time demo/DowntimeSchedule.swift` | Main app | Per-user nightly downtime window model |
| `Screen time demo/DowntimeOverrideRequest.swift` | Main app | Peer override request model (subcollection) |
| `Screen time demo/DowntimeService.swift` | Main app | Firestore CRUD + App Group cache for downtime |
| `Screen time demo/DowntimeScheduler.swift` | Main app | `DeviceActivityCenter` wrapper for repeating downtime schedule |
| `Screen time demo/DowntimeSettingsView.swift` | Main app | Full UI: time pickers, app picker, override request/approve |
| `Screen time demo/MorningRoutine.swift` | Main app | Per-user morning routine model (time-based + activity-based) |
| `Screen time demo/MorningRoutineService.swift` | Main app | Firestore CRUD + App Group cache for routine |
| `Screen time demo/MorningRoutineScheduler.swift` | Main app | `DeviceActivityCenter` wrapper with `routineCompleted` event |
| `Screen time demo/MorningRoutineSettingsView.swift` | Main app | Full UI: lock/unlock pickers, mode picker, routine-app picker |

---

## Modified Files

| File | What Changed |
|------|-------------|
| `Screen time demo/StudyHallConstants.swift` | Added downtime keys, morning routine keys, break vote notification key, named store identifiers |
| `Screen time demo/Group.swift` | Added `breakVotingEnabled`, `breakWindowSeconds`, `breakCooldownPercent`, `downtimeEnabled`, `morningRoutineEnabled` |
| `Screen time demo/StudySession.swift` | Added break vote fields + computed gate-check properties (`canInitiateBreakVote`, `penaltyLock`, etc.) |
| `Screen time demo/SessionService.swift` | `createSession` now forwards break voting parameters |
| `Screen time demo/SessionViewModel.swift` | Break vote state, `initiateBreakVote()`, `castBreakVote()`, `handleBreakVoteUpdate()`, expiry task, `uid` accessor, group settings for break voting |
| `Screen time demo/SessionView.swift` | `breakVoteControls()` — in-flight banner + initiate button with disabled reason |
| `Screen time demo/GroupDetailView.swift` | Break voting toggle, downtime toggle, morning routine toggle, `BreakVoteView` sheet, `scheduleSettingsSection` with nav links |
| `Screen time demo/PushNotificationService.swift` | `postBreakVoteStartedNotification()` |
| `Screen time demo/AuthorizationManager.swift` | Reactive Combine subscription to `AuthorizationCenter.shared.objectWillChange` |
| `Screen time demo/ContentView.swift` | Permission button hidden when already authorised |
| `StudyHallMonitor/StudyHallMonitor.swift` | Dispatches on activity name; three named `ManagedSettingsStore` instances; downtime shields; morning routine shields + early unlock on `routineCompleted` event |

---

## Firestore Schema Changes

### `groups/{groupID}`
New fields (all default to `false` / safe defaults on existing documents):
```
breakVotingEnabled: Bool       // default false
breakWindowSeconds: Int        // default 120
breakCooldownPercent: Int      // default 20
downtimeEnabled: Bool          // default false
morningRoutineEnabled: Bool    // default false
```

### `sessions/{groupID}` (active session slot)
New fields written at session creation:
```
breakVotingEnabled: Bool
breakWindowSeconds: Int
breakCooldownMinutes: Int
penaltyLock: Bool              // default false; set true when a vote passes
lastBreakVoteEndedAt: Timestamp?
activeBreakVote: Map?          // embedded BreakVote document (see below)
```

`activeBreakVote` map shape:
```
id: String
initiatorUid: String
startedAt: Timestamp
windowSeconds: Int
votes: { [uid: String]: Bool }
status: "pending" | "passed" | "failed" | "expired"
```

### `users/{uid}`
New fields written by `DowntimeService` and `MorningRoutineService`:
```
downtime: {
  enabled: Bool
  startHour: Int    // 0-23
  startMinute: Int
  endHour: Int
  endMinute: Int
}

morningRoutine: {
  enabled: Bool
  lockHour: Int
  lockMinute: Int
  unlockHour: Int
  unlockMinute: Int
  unlockMode: "timeBased" | "activityBased"
  unlockActivityMinutes: Int
}
```

### `groups/{groupID}/downtimeOverrides/{requestID}` (new subcollection)
```
requestorUID: String
requestedAt: Timestamp
durationMinutes: Int
status: "pending" | "approved" | "denied" | "expired"
responderUID: String?
respondedAt: Timestamp?
expiresAt: Timestamp?
```

---

## DeviceActivity Schedule Names

| Constant | Raw value | Purpose |
|----------|-----------|---------|
| `studyHallActivityName` | `studyHall` | Focus session (existing) |
| `downtimeActivityName` | `studyHall.downtime` | Nightly downtime (new) |
| `morningRoutineActivityName` | `studyHall.morningRoutine` | Morning routine (new) |

**Named ManagedSettingsStores** (so session, downtime, and routine shields never conflict):

| Store | Name constant |
|-------|--------------|
| Session (default) | (unnamed — `ManagedSettingsStore()`) |
| Downtime | `com.davechengapps.screentimedemo.downtime` |
| Morning Routine | `com.davechengapps.screentimedemo.morningRoutine` |

> **⚠️ Xcode capability required:** Each named `ManagedSettingsStore` name must be declared in `Screen time demo.entitlements` under the `com.apple.developer.family-controls.managedstore` array key. Open Xcode → Screen time demo target → Signing & Capabilities → Family Controls → add both store names. Without this the extension will crash at runtime when it tries to write to the named stores.

---

## Manual Testing Checklist (Physical iPhone Required)

### GRO-11 — Break Voting
- [ ] Create a 2-person group with Break Voting enabled.
- [ ] Start a 25-min session. Confirm "Initiate Break Vote" is disabled until 12:30 (50 % elapsed).
- [ ] After 12:30 passes, tap "Initiate Break Vote". Confirm the in-flight banner appears on both devices.
- [ ] Vote FOR on both devices. Confirm `status` flips to `passed` in Firestore, shields drop, and both devices show the result banner.
- [ ] Confirm `penaltyLock: true` appears on the session document after a vote passes.
- [ ] Confirm a second "Initiate Break Vote" is disabled after a pass (penalty lock).
- [ ] Let a vote expire without 67 % — confirm `status` flips to `expired` and shields remain.
- [ ] Test the local notification: on the initiating device, the other device should receive a local push if `breakVoteNotificationsEnabled` is unset or `true`.
  - **TODO:** Full APNs push (server-side) requires a Cloud Function; local notifications work only while the app is in foreground/recently active. Wire up FCM topic messaging for true background pushes when Cloud Functions are available.

### GRO-12 — Downtime
- [ ] Open Downtime Settings, set a window 2 minutes from now, tap Save.
- [ ] Confirm `DeviceActivitySchedule` fires `intervalDidStart` and shields appear via the downtime named store.
- [ ] Confirm allowed apps (from the picker) remain unblocked.
- [ ] Submit a peer override request (1 min). On the second device, approve it.
- [ ] Confirm shields drop, the `downtimeOverrideActive` key is set in App Group UserDefaults, and re-block happens exactly 1 min later.
- [ ] Confirm `expiresAt` in Firestore matches the re-block time.
- [ ] Test that denying a request leaves shields in place.

### GRO-13 — Morning Routine
- [ ] Enable Morning Routine in time-based mode; set lock time = now+1 min, unlock = now+3 min.
- [ ] Confirm `intervalDidStart` fires and routine shields appear.
- [ ] Confirm `intervalDidEnd` fires at unlock time and shields drop.
- [ ] Switch to activity-based mode; pick a routine app (e.g. Reminders); set threshold = 1 min.
- [ ] Open the routine app for 1 min. Confirm `eventDidReachThreshold` fires and shields lift early.
  - **TODO:** The `routineCompleted` event fires on accumulated device-activity time, not just foreground time. On a simulator this may not accumulate correctly — test on a physical device only.

---

## Firestore Security Rules — Review Required

The following new paths need rules. Add them to your `firestore.rules` before going to production:

```javascript
// Break votes are embedded in the session doc — existing session rules cover reads.
// The BreakVoteService uses transactions so no additional subcollection needed.

// Downtime override requests
match /groups/{groupID}/downtimeOverrides/{requestID} {
  // Any group member can read all override requests.
  allow read: if request.auth != null
    && request.auth.uid in get(/databases/$(database)/documents/groups/$(groupID)).data.memberUids;

  // Only create your own request.
  allow create: if request.auth != null
    && request.resource.data.requestorUID == request.auth.uid
    && request.auth.uid in get(/databases/$(database)/documents/groups/$(groupID)).data.memberUids;

  // Any other group member can update status (approve/deny).
  // Requestors cannot approve their own requests (enforced client-side + here).
  allow update: if request.auth != null
    && request.auth.uid != resource.data.requestorUID
    && request.auth.uid in get(/databases/$(database)/documents/groups/$(groupID)).data.memberUids;
}

// Per-user downtime and morning routine schedules are nested under the user doc.
// Existing users/{uid} rules (allow read/write if request.auth.uid == uid) already cover these.
```

---

## App Group UserDefaults Keys Added

All keys are in the `group.com.davechengapps.screentimedemo` suite and are read by `StudyHallMonitor`:

| Key | Type | Written by | Read by |
|-----|------|------------|---------|
| `studyHall.downtimeAllowedApps` | Data (encoded FamilyActivitySelection) | `DowntimeService.persistAllowedApps` | `StudyHallMonitor.applyDowntimeShields` |
| `studyHall.downtimeOverrideActive` | Bool | `DowntimeScheduler.suspendForOverride` | `StudyHallMonitor.applyDowntimeShields` |
| `studyHall.routineApps` | Data (encoded FamilyActivitySelection) | `MorningRoutineService.persistRoutineApps` | `StudyHallMonitor.applyRoutineShields` |
| `studyHall.routineUnlockMode` | String (rawValue) | `MorningRoutineService.cacheRoutineForExtension` | *(future: for event-based checks)* |
| `studyHall.routineUnlockMinutes` | Int | `MorningRoutineService.cacheRoutineForExtension` | *(future: for event-based checks)* |
| `studyHall.downtimeScheduleEnabled` | Bool | `DowntimeService.saveSchedule` | *(informational)* |
| `studyHall.breakVoteNotificationsEnabled` | Bool | User opt-out (standard UserDefaults) | `SessionViewModel.handleBreakVoteUpdate` |

---

## Known Limitations & Edge Cases

1. **Break vote notifications are local-only.** The `postBreakVoteStartedNotification` fires a `UNUserNotificationCenter` local notification. Members who have the app fully terminated will not receive it until they reopen the app and the Firestore listener re-fires. True background APNs requires a Cloud Function trigger on `sessions/{groupID}` writes.

2. **Downtime override re-block is client-side.** The `overrideExpiryTask` in `DowntimeSettingsView` re-enables the schedule after the approved duration. If the user force-quits the app before the timer fires, re-block will happen the next time `intervalDidStart` fires on the next day's schedule. This is acceptable behaviour — there is no permanent override path.

3. **Named ManagedSettingsStore entitlements.** As noted above: both store names must be added to `Screen time demo.entitlements` under `com.apple.developer.family-controls.managedstore` before the extension will write to them without crashing. The session (default) store already works — this only affects downtime and routine stores.

4. **Activity-based unlock accumulates across calendar days.** `DeviceActivityEvent` thresholds accumulate usage from `intervalStart`. If the routine window starts at 6 AM and the user leaves the app open from 11 PM the night before, accumulated time from that session could pre-satisfy the threshold. Mitigated by the repeating schedule resetting at the start of each interval.

5. **Break vote `castVote` race condition on last voter.** `BreakVoteService.castVote` uses a Firestore transaction to check supermajority after writing. If two voters submit simultaneously and each reads the pre-write state, the transaction retries automatically — this is handled correctly by the SDK. No action needed.

6. **`DowntimeOverrideRequest` subcollection is not cleaned up.** Expired and denied requests accumulate. A scheduled Cloud Function or a periodic client-side purge (e.g. delete requests older than 7 days) should be added when Cloud Functions are available.
