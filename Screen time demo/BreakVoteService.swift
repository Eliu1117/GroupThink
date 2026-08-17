//
//  BreakVoteService.swift
//  Screen time demo
//
//  All Firestore writes for the GRO-11 break voting system.
//  All vote state lives in the `activeBreakVote` embedded map on the session
//  document (`groups/{groupId}/sessions/current`), so it is delivered in the
//  same snapshot as the rest of the session and requires no extra listener.
//

import FirebaseFirestore
import Foundation

enum BreakVoteServiceError: LocalizedError {
    case noActiveSession
    case voteAlreadyInFlight
    case notEligibleToVote
    case voteNotFound
    case alreadyResolved

    var errorDescription: String? {
        switch self {
        case .noActiveSession:      return "No active session found."
        case .voteAlreadyInFlight:  return "A break vote is already in progress."
        case .notEligibleToVote:    return "You are not eligible to cast a vote."
        case .voteNotFound:         return "No pending vote was found."
        case .alreadyResolved:      return "This vote has already been resolved."
        }
    }
}

final class BreakVoteService {
    static let shared = BreakVoteService()
    private let db = Firestore.firestore()
    private init() {}

    private func sessionRef(for groupID: String) -> DocumentReference {
        db.collection("groups").document(groupID).collection("sessions").document("current")
    }

    // MARK: - Initiate

    /// Writes a fresh `activeBreakVote` map to the session document.
    /// Caller must verify all gate conditions (time lock, cooldown, not on a break)
    /// before calling — the service does a lightweight idempotency check only.
    func initiateVote(
        groupID: String,
        initiatorUID: String,
        windowSeconds: Int
    ) async throws {
        let ref = sessionRef(for: groupID)

        try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard snapshot.exists else {
                errorPointer?.pointee = BreakVoteServiceError.noActiveSession as NSError
                return nil
            }

            // Guard: no vote already in flight
            if let existing = snapshot.data()?["activeBreakVote"] as? [String: Any],
               let statusRaw = existing["status"] as? String,
               statusRaw == BreakVoteStatus.pending.rawValue {
                errorPointer?.pointee = BreakVoteServiceError.voteAlreadyInFlight as NSError
                return nil
            }

            let voteMap: [String: Any] = [
                "id": UUID().uuidString,
                "initiatorUid": initiatorUID,
                "startedAt": FieldValue.serverTimestamp(),
                "windowSeconds": windowSeconds,
                "votes": [:],
                "status": BreakVoteStatus.pending.rawValue,
            ]

            transaction.updateData(
                ["activeBreakVote": voteMap],
                forDocument: ref
            )
            return nil
        }
        print("[BreakVote] Vote initiated by \(initiatorUID) in group \(groupID)")
    }

    // MARK: - Cast vote

    /// Records the voter's choice on the `activeBreakVote.votes` sub-map, then
    /// attempts to resolve the vote immediately if a supermajority has been reached.
    func castVote(
        groupID: String,
        voterUID: String,
        inFavor: Bool,
        totalParticipants: Int
    ) async throws {
        let ref = sessionRef(for: groupID)

        try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard var voteMap = snapshot.data()?["activeBreakVote"] as? [String: Any],
                  let statusRaw = voteMap["status"] as? String,
                  statusRaw == BreakVoteStatus.pending.rawValue
            else {
                errorPointer?.pointee = BreakVoteServiceError.voteNotFound as NSError
                return nil
            }

            // Record this vote.
            var votes = voteMap["votes"] as? [String: Bool] ?? [:]
            votes[voterUID] = inFavor
            voteMap["votes"] = votes

            // Resolve immediately when a supermajority is reached in either direction (GRO-29).
            let yesCount = votes.values.filter { $0 }.count
            let noCount  = votes.values.filter { !$0 }.count

            if Double(yesCount) / Double(totalParticipants) >= 0.67 {
                // 67 % FOR — vote passes immediately.
                voteMap["status"] = BreakVoteStatus.passed.rawValue
                transaction.updateData(
                    [
                        "activeBreakVote": voteMap,
                        "lastBreakVoteEndedAt": FieldValue.serverTimestamp(),
                    ],
                    forDocument: ref
                )
            } else if Double(noCount) / Double(totalParticipants) >= 0.67 {
                // 67 % AGAINST — vote fails immediately; no penalty lock on the session.
                voteMap["status"] = BreakVoteStatus.failed.rawValue
                transaction.updateData(
                    [
                        "activeBreakVote": voteMap,
                        "lastBreakVoteEndedAt": FieldValue.serverTimestamp(),
                    ],
                    forDocument: ref
                )
            } else {
                // Outcome still undecided — record the vote and wait for more.
                transaction.updateData(
                    ["activeBreakVote": voteMap],
                    forDocument: ref
                )
            }
            return nil
        }
        print("[BreakVote] \(voterUID) voted \(inFavor ? "FOR" : "AGAINST") in group \(groupID)")
    }

    // MARK: - Expire / fail

    /// Called when the 2-minute vote window expires without a supermajority.
    /// Uses a transaction to avoid overwriting a vote that was already resolved
    /// by a concurrent supermajority write.
    func expireVote(groupID: String, voteID: String) async throws {
        let ref = sessionRef(for: groupID)

        try await db.runTransaction { transaction, errorPointer in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }

            guard var voteMap = snapshot.data()?["activeBreakVote"] as? [String: Any],
                  let storedID = voteMap["id"] as? String,
                  storedID == voteID,                          // guard against stale expiry
                  let statusRaw = voteMap["status"] as? String,
                  statusRaw == BreakVoteStatus.pending.rawValue
            else {
                // Already resolved — nothing to do.
                return nil
            }

            voteMap["status"] = BreakVoteStatus.expired.rawValue
            transaction.updateData(
                [
                    "activeBreakVote": voteMap,
                    "lastBreakVoteEndedAt": FieldValue.serverTimestamp(),
                ],
                forDocument: ref
            )
            return nil
        }
        print("[BreakVote] Vote \(voteID) expired in group \(groupID)")
    }
}
