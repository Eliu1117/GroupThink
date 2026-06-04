//
// Cloud Functions for Study Hall.
//
// Sends push notifications to a group's members when a session starts and when a
// member leaves early or opens a blocked app. Keeps all FCM credentials server-side.
//

import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

initializeApp();
const db = getFirestore();

/**
 * Collects FCM tokens for every member of a group, optionally excluding one uid.
 */
async function tokensForGroup(groupId, excludeUid) {
  const groupSnap = await db.doc(`groups/${groupId}`).get();
  if (!groupSnap.exists) return [];

  const memberUids = (groupSnap.data().memberUids || []).filter(
    (uid) => uid !== excludeUid
  );
  if (memberUids.length === 0) return [];

  const tokens = [];
  for (const uid of memberUids) {
    const userSnap = await db.doc(`users/${uid}`).get();
    if (userSnap.exists) {
      tokens.push(...(userSnap.data().fcmTokens || []));
    }
  }
  return [...new Set(tokens)];
}

async function notify(tokens, title, body) {
  if (tokens.length === 0) return;
  await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
  });
}

export const onSessionWrite = onDocumentWritten(
  "groups/{groupId}/sessions/{sessionId}",
  async (event) => {
    const { groupId } = event.params;
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return;

    // Session became active -> tell everyone to lock in.
    if (before?.status !== "active" && after.status === "active") {
      const hostName = after.participants?.[after.hostUid]?.displayName || "Someone";
      const tokens = await tokensForGroup(groupId, after.hostUid);
      await notify(tokens, "Study hall started", `${hostName} started a study hall. Lock in!`);
      return;
    }

    // A participant's state changed to left/opened -> shame-wall ping.
    if (before?.participants && after.participants) {
      for (const uid of Object.keys(after.participants)) {
        const prev = before.participants[uid]?.state;
        const next = after.participants[uid]?.state;
        if (prev === next) continue;

        const name = after.participants[uid]?.displayName || "Someone";
        const tokens = await tokensForGroup(groupId, uid);
        if (next === "left") {
          await notify(tokens, "Someone bailed", `${name} left the study hall early.`);
        } else if (next === "opened") {
          await notify(tokens, "Caught slipping", `${name} opened a blocked app.`);
        }
      }
    }
  }
);
