//
//  MorningRoutineService.swift  (GRO-32: class renamed to RoutineService; file name kept for Xcode compat)
//  Screen time demo
//
//  Reads/writes routine schedules to Firestore and caches configuration
//  in App Group UserDefaults for the monitor extension.
//
//  FIRESTORE KEY NOTE: Schedules are stored at users/{uid} under the key "morningRoutine".
//  This key is preserved intentionally so existing Firestore documents are not broken.
//

import FamilyControls
import FirebaseFirestore
import Foundation

final class RoutineService {
    static let shared = RoutineService()
    private let db = Firestore.firestore()
    private init() {}

    private func userRef(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    // MARK: - Schedule

    func saveRoutine(uid: String, routine: Routine) async throws {
        // Key "morningRoutine" retained for Firestore backward compatibility (GRO-32).
        try await userRef(uid).setData(["morningRoutine": routine.asMap()], merge: true)
        cacheRoutineForExtension(routine)
        print("[Routine] Saved for \(uid): \(routine.formattedLockTime()) – \(routine.formattedUnlockTime())")
    }

    func loadRoutine(uid: String) async throws -> Routine {
        let snap = try await userRef(uid).getDocument()
        guard
            let data = snap.data(),
            let map = data["morningRoutine"] as? [String: Any],
            let routine = Routine(map: map)
        else {
            return .default
        }
        return routine
    }

    /// Caches the routine unlock parameters in App Group UserDefaults so the
    /// monitor extension can react to the `routineCompleted` event without Firestore access.
    func cacheRoutineForExtension(_ routine: Routine) {
        guard let shared = UserDefaults(suiteName: StudyHallConstants.appGroupID) else { return }
        shared.set(routine.unlockMode.rawValue, forKey: StudyHallConstants.routineUnlockModeKey)
        shared.set(routine.unlockActivityMinutes, forKey: StudyHallConstants.routineUnlockMinutesKey)
    }

    // MARK: - Routine apps

    func persistRoutineApps(_ selection: FamilyActivitySelection) {
        guard
            let data = try? PropertyListEncoder().encode(selection),
            let shared = UserDefaults(suiteName: StudyHallConstants.appGroupID)
        else { return }
        shared.set(data, forKey: StudyHallConstants.routineAppsKey)
        print("[Routine] Cached routine apps (\(selection.applicationTokens.count) apps)")
    }

    func loadRoutineApps() -> FamilyActivitySelection {
        guard
            let shared = UserDefaults(suiteName: StudyHallConstants.appGroupID),
            let data = shared.data(forKey: StudyHallConstants.routineAppsKey),
            let selection = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }
}
