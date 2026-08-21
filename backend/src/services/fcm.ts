/**
 * FCM (Firebase Cloud Messaging) dispatch — STUBBED, per
 * docs/technical/architecture/backend-mvp-plan.md Task 7's explicit scoping:
 * "blocked on a Firebase project existing (currently 'not set up' per
 * build-status.md's Environment Setup table)". This file exists so the rest
 * of the emergency engine (WS events, timers, resolution paths) can be
 * built, wired, and verified without waiting on that external setup — NOT
 * because the FCM leg is unimportant. It is, per
 * technical/systems/push-notifications.md, the actual safety-critical part
 * for a rider who's out of Bluetooth/PTT range and needs the DND-bypass
 * "Critical Alert" push to reach a silenced phone. Do not read this file's
 * existence as "emergency alerts work end to end" — they don't, until this
 * is a real Firebase Admin SDK call.
 *
 * TODO(firebase-setup): once a Firebase project exists and its Admin SDK
 * service-account credentials are available as a real secret (same
 * never-commit discipline as JWT_SECRET, see .env.example), replace the body
 * of dispatchEmergencyPush with a real
 * admin.messaging().sendEachForMulticast(...) call using the payload shape
 * documented in technical/systems/push-notifications.md's "Emergency Alert:
 * DND Bypass" section (android.notification.channel_id: 'emergency',
 * notification_priority: PRIORITY_MAX; apns-priority: 10,
 * interruption-level: critical). Device FCM tokens also don't exist yet —
 * push-notifications.md documents them as living on the (not-yet-built)
 * Postgres `users` table, another MVP gap this stub sidesteps rather than
 * papering over: there is currently nowhere to even look up which device
 * token to send to.
 */

export interface EmergencyPushTarget {
  userId: string;
}

export interface EmergencyPushPayload {
  partyId: string;
  stoppedUserId: string;
  stoppedUserName: string;
  distanceBehindKm: number | null;
}

/**
 * No-op stand-in for the real FCM dispatch. Logs clearly (so a test run or a
 * future engineer can see this fired, and that it's a stub, not silence) and
 * never throws — a missing Firebase config must never crash the emergency
 * engine or prevent `emergency:full_alert` from reaching connected WS
 * clients, since the WS broadcast (not this) is what the currently-built
 * system can actually deliver.
 */
export async function dispatchEmergencyPush(
  targets: EmergencyPushTarget[],
  payload: EmergencyPushPayload,
): Promise<void> {
  // eslint-disable-next-line no-console
  console.log(
    '[fcm] STUB — Firebase project not configured (see build-status.md). Would have sent a ' +
      'priority:high / DND-bypassing emergency push to %d device(s) for party %s, stopped rider %s (%s). ' +
      'No real push was sent — TODO(firebase-setup) in src/services/fcm.ts.',
    targets.length,
    payload.partyId,
    payload.stoppedUserId,
    payload.stoppedUserName || '(no name on record)',
  );
  return Promise.resolve();
}
