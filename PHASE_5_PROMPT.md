# Master Prompt for AI Agent: Phase 5 (Stats & Retention)

**Role:** You are an expert iOS developer specializing in SwiftUI and Firebase. You are working on the "Study Hall" native iOS app.

## Project Context
"Study Hall" is a group study app using Screen Time (Family Controls) to block distracting apps. Users join groups and host study sessions. 
- **Current State:** Phases 0 through 4 (Auth, Groups, Sessions, Social Presence with Live State) are fully complete and functional.
- **Tech Stack:** SwiftUI, Firebase (Auth, Firestore), Swift Concurrency (`async/await`), and `@MainActor` for UI updates.
- **Architecture:** We use MVVM (`ObservableObject`, `@Published`) and singletons for core services (`GroupService`, `SessionService`, `UserService`).

## Task: Implement Phase 5 — Stats & Retention
Your goal is to perfectly implement Phase 5 without errors. You must write complete, production-ready Swift code, handling all edge cases (network errors, stale data, optional unwrapping) and ensuring UI updates are thread-safe (`@MainActor`).

### Phase 5 Requirements Breakdown

#### Step 1: Track Focus Minutes
- **Logic:** When a session ends (either timer expires or host ends it early), the app must compute the `durationMin` of the session.
- **Condition:** Only award focus minutes to participants whose `state` remained `"focused"` the entire session. Do not reward users who `"left"` or `"opened"` a blocked app.
- **Implementation:** In `SessionService.swift` (or where session completion is handled), use `FieldValue.increment(Int64(durationMin))` to atomically update `stats.focusMinutes` on the `users/{uid}` document.

#### Step 2: Individual Streaks
- **Logic:** We want to encourage daily use.
- **Data Model:** Add `lastSessionDate` (Timestamp) to the `users/{uid}/stats` object.
- **Calculation:** Upon a successful session completion:
  1. Fetch the user's current `lastSessionDate`.
  2. If `lastSessionDate` is *yesterday* (calendar day, using user's local timezone), increment `currentStreak` by 1.
  3. If `lastSessionDate` is *today*, do nothing to the streak.
  4. If `lastSessionDate` is *before yesterday* (or nil), reset `currentStreak` to 1.
  5. Update `lastSessionDate` to `now`.
- **Implementation:** Perform this calculation safely when updating focus minutes. Consider doing this in a Firestore Transaction or Batch write to ensure consistency.

#### Step 3: Group Streaks
- **Logic:** A group streak survives only if *every* member of the group completed at least one successful session that calendar day.
- **Data Model:** On the `groups/{groupId}` doc, add `currentGroupStreak` (Int) and `lastGroupStreakUpdate` (Timestamp).
- **Implementation:** This is tricky client-side. When a session ends:
  - Check if the group's `lastGroupStreakUpdate` is today. If so, nothing needs to be done.
  - If not, verify if *all* members have their individual `lastSessionDate` as today.
  - If they do, increment `currentGroupStreak` on the group document and set `lastGroupStreakUpdate` to today.
  - *Note:* Propose the most robust way to handle this without Cloud Functions, relying strictly on client-side Swift.

#### Step 4: Group Leaderboard UI
- **Logic:** Create a Leaderboard view inside the group context showing members ranked by their total focus minutes.
- **UI:** A new SwiftUI view `GroupLeaderboardView` (or integrate it into the existing `GroupDetailView` as a tab or section).
- **Data:** You will need to fetch the `stats.focusMinutes` and `currentStreak` for all members in the `memberUids` array of the current group.
- **Requirements:** The UI should be polished, matching standard modern iOS list views, showing an avatar placeholder, display name, total minutes, and a fire icon (🔥) with the user's streak.

---

### Strict Guidelines for the Agent

1. **No Placeholders:** Write the full logic for the Swift files. Do not write `// add logic here`.
2. **Swift Concurrency:** Use `async/await`. Avoid completion handlers. Wrap UI updates in `@MainActor` or `Task { @MainActor in }`.
3. **Firestore Safety:** 
   - Use `FieldValue.increment()` for counters to prevent race conditions.
   - Use `WriteBatch` or `Transaction` when updating multiple documents (e.g., updating session status + user stats simultaneously).
4. **Data Models:** Ensure you provide the updated Swift `struct` definitions (e.g., `UserProfile`, `Group`) conforming to `Codable` to support the new streak and timestamp fields. Use `@ServerTimestamp` or `Timestamp` from Firebase.
5. **Security Rules:** Provide the necessary updates to `firestore.rules` allowing users to update their own stats, and group members to update group streaks.

### Deliverables Expected From You
1. Updated Swift data models (`UserProfile.swift`, `Group.swift`).
2. Updated `SessionService.swift` containing the end-of-session calculation logic for minutes and streaks.
3. A new or updated `GroupLeaderboardViewModel.swift`.
4. A new SwiftUI file `GroupLeaderboardView.swift`.
5. Any necessary integration code (e.g., placing the Leaderboard button in `GroupDetailView`).
6. The updated `firestore.rules` block.

**Begin your response by confirming your understanding of the data model changes, then provide the code.**