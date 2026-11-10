// TripKhata Cloud Functions (codebase "tripkhata").
// The Firebase project is shared with other apps: deploy ONLY this codebase with
//   firebase deploy --only functions:tripkhata
// so the other apps' functions are never touched.

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { defineString } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const { changeKind, buildMessage } = require('./message');

admin.initializeApp();

// Firestore triggers must run in the database's region. The CLI asks for this
// on the first deploy (Firebase console → Firestore → the location shown at the
// top, e.g. asia-south1; use us-central1 for nam5 and europe-west1 for eur3).
const FIRESTORE_REGION = defineString('FIRESTORE_REGION', {
  default: 'asia-south1',
  description: 'Region of your Firestore database (Firebase console → Firestore)',
});

const TRIPS = 'tripkhata_trips';
const USERS = 'tripkhata_users';
const DEAD_TOKEN = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/** Someone added, edited or deleted an expense → push to everyone else in the trip. */
exports.tripkhataExpenseNotify = onDocumentWritten(
  { document: `${TRIPS}/{tripId}/expenses/{expenseId}`, region: FIRESTORE_REGION },
  async (event) => {
    const before = event.data && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data && event.data.after.exists ? event.data.after.data() : null;
    const kind = changeKind(before, after);
    if (!kind) return;

    const { tripId } = event.params;
    const by = after.editedBy;
    const db = admin.firestore();
    const tripRef = db.collection(TRIPS).doc(tripId);

    const [tripSnap, membersSnap] = await Promise.all([tripRef.get(), tripRef.collection('members').get()]);
    if (!tripSnap.exists) return;
    const trip = tripSnap.data();
    const recipients = (trip.memberUids || []).filter((u) => u && u !== by);
    if (!recipients.length) return;

    const members = membersSnap.docs.map((d) => d.data());
    const author = (members.find((m) => m.uid === by) || {}).name || 'Someone';
    const shares = after.shares || (before && before.shares) || {};

    const userSnaps = await db.getAll(...recipients.map((u) => db.collection(USERS).doc(u)));

    await Promise.all(
      userSnaps.map(async (snap) => {
        if (!snap.exists) return;
        const user = snap.data();
        const tokens = (user.tokens || []).filter(Boolean);
        if (user.notify === false || !tokens.length) return;

        const me = members.find((m) => m.uid === snap.id);
        const msg = buildMessage({
          kind,
          author,
          tripName: trip.name || 'your trip',
          title: after.title || (before && before.title),
          amount: after.amount || 0,
          myShare: me ? shares[me.id] || 0 : 0,
        });

        const res = await admin.messaging().sendEachForMulticast({
          tokens,
          notification: msg,
          data: { tripId, expenseId: event.params.expenseId, kind },
          android: {
            priority: 'high',
            // Same channel and tag as the app's local notices, so one trip
            // shows one notification that updates instead of a pile.
            notification: { channelId: 'trip_activity', tag: tripId },
          },
        });

        const dead = [];
        res.responses.forEach((r, i) => {
          if (!r.success && r.error && DEAD_TOKEN.has(r.error.code)) dead.push(tokens[i]);
        });
        if (dead.length) {
          await snap.ref.update({ tokens: admin.firestore.FieldValue.arrayRemove(...dead) });
        }
        logger.info('expense push', { tripId, kind, to: snap.id, sent: res.successCount, dead: dead.length });
      }),
    );
  },
);
