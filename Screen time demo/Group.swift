//
//  Group.swift
//  Screen time demo
//
//  Firestore document model for `groups/{groupId}`.
//

import FirebaseFirestore
import Foundation

struct Group: Identifiable, Equatable, Hashable {
    /// Document ID (`groupId`).
    let id: String
    let name: String
    let inviteCode: String
    let createdBy: String
    let memberUids: [String]

    init?(
        id: String,
        document: DocumentSnapshot
    ) {
        guard document.exists, let data = document.data() else { return nil }

        guard
            let name = data["name"] as? String,
            let inviteCode = data["inviteCode"] as? String,
            let createdBy = data["createdBy"] as? String,
            let memberUids = data["memberUids"] as? [String]
        else {
            return nil
        }

        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.createdBy = createdBy
        self.memberUids = memberUids
    }

    init(
        id: String,
        name: String,
        inviteCode: String,
        createdBy: String,
        memberUids: [String]
    ) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.createdBy = createdBy
        self.memberUids = memberUids
    }

    /// Generates a short, human-friendly invite code (ambiguous characters omitted).
    static func generateInviteCode(length: Int = 6) -> String {
        let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
