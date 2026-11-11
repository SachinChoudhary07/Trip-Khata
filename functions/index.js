// TripKhata Cloud Functions (codebase "tripkhata").
// The Firebase project is shared with other apps: deploy ONLY this codebase with
//   firebase deploy --only functions:tripkhata
// so the other apps' functions are never touched.

const { onDocumentWritten, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const functionsV1 = require('firebase-functions/v1');
const { defineString, defineSecret } = require('firebase-functions/params');
const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectsCommand,
  ListObjectsV2Command,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const { changeKind, buildMessage } = require('./message');
const photos = require('./photos');

admin.initializeApp();

// Firestore triggers must run in the database's region. The CLI asks for this
// on the first deploy (Firebase console → Firestore → the location shown at the
// top, e.g. asia-south1; use us-central1 for nam5 and europe-west1 for eur3).
const FIRESTORE_REGION = defineString('FIRESTORE_REGION', {
  default: 'asia-south1',
  description: 'Region of your Firestore database (Firebase console → Firestore)',
});

// Cloudflare R2 for trip photos. Set with:
//   firebase functions:secrets:set R2_ACCESS_KEY_ID
//   firebase functions:secrets:set R2_SECRET_ACCESS_KEY
// and R2_ACCOUNT_ID / R2_BUCKET when the CLI asks on deploy (see docs/CLOUD_SETUP.md).
const R2_ACCOUNT_ID = defineString('R2_ACCOUNT_ID', { description: 'Cloudflare account ID (R2 overview page)' });
const R2_BUCKET = defineString('R2_BUCKET', { default: 'tripkhata-photos', description: 'R2 bucket for trip photos' });
const R2_ACCESS_KEY_ID = defineSecret('R2_ACCESS_KEY_ID');
const R2_SECRET_ACCESS_KEY = defineSecret('R2_SECRET_ACCESS_KEY');
const R2_SECRETS = [R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY];

let r2Client;
function r2() {
  if (!r2Client) {
    r2Client = new S3Client({
      region: 'auto',
      endpoint: `https://${R2_ACCOUNT_ID.value()}.r2.cloudflarestorage.com`,
      credentials: { accessKeyId: R2_ACCESS_KEY_ID.value(), secretAccessKey: R2_SECRET_ACCESS_KEY.value() },
    });
  }
  return r2Client;
}

/** Deletes R2 objects in batches of 1000. Never throws. */
async function deleteR2(keys) {
  for (let i = 0; i < keys.length; i += 1000) {
    const chunk = keys.slice(i, i + 1000);
    try {
      await r2().send(new DeleteObjectsCommand({
        Bucket: R2_BUCKET.value(),
        Delete: { Objects: chunk.map((Key) => ({ Key })), Quiet: true },
      }));
    } catch (e) {
      logger.warn('r2 delete failed', { count: chunk.length, error: String(e) });
    }
  }
}

const TRIPS = 'tripkhata_trips';
const USERS = 'tripkhata_users';
const CODES = 'tripkhata_codes';
const STORAGE_ROOT = 'tripkhata';

async function deleteBill(path) {
  if (!path) return;
  try {
    await admin.storage().bucket().file(path).delete({ ignoreNotFound: true });
  } catch (e) {
    logger.warn('bill delete failed', { path, error: String(e) });
  }
}
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
    // Bill photo replaced, removed or its expense deleted: drop the old file.
    if (before && before.bill && (!after || after.deleted || after.bill !== before.bill)) {
      await deleteBill(before.bill);
    }
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

/** A shared trip was deleted for everyone: remove its data, join code and bill photos. */
exports.tripkhataTripDeleted = onDocumentDeleted(
  { document: `${TRIPS}/{tripId}`, region: FIRESTORE_REGION, secrets: R2_SECRETS },
  async (event) => {
    const { tripId } = event.params;
    const trip = event.data ? event.data.data() : {};
    const db = admin.firestore();
    await db.recursiveDelete(db.collection(TRIPS).doc(tripId)); // leftover subcollections
    if (trip && trip.joinCode) await db.collection(CODES).doc(trip.joinCode).delete().catch(() => {});
    await admin.storage().bucket().deleteFiles({ prefix: `${STORAGE_ROOT}/${tripId}/` }).catch((e) =>
      logger.warn('trip files delete failed', { tripId, error: String(e) }),
    );
    // Trip photos in R2.
    try {
      let token;
      do {
        const page = await r2().send(new ListObjectsV2Command({
          Bucket: R2_BUCKET.value(),
          Prefix: photos.prefix(tripId),
          ContinuationToken: token,
        }));
        await deleteR2((page.Contents || []).map((o) => o.Key));
        token = page.IsTruncated ? page.NextContinuationToken : undefined;
      } while (token);
    } catch (e) {
      logger.warn('trip photos delete failed', { tripId, error: String(e) });
    }
    logger.info('trip deleted', { tripId });
  },
);

/**
 * Account deleted (from the app, or by you in the Firebase console):
 * remove push tokens, take the person out of every trip and unlink their
 * member rows. Trips nobody is left in are deleted completely.
 */
exports.tripkhataAccountDeleted = functionsV1.auth.user().onDelete(async (user) => {
  const uid = user.uid;
  const db = admin.firestore();
  await db.collection(USERS).doc(uid).delete().catch(() => {});
  const trips = await db.collection(TRIPS).where('memberUids', 'array-contains', uid).get();
  for (const t of trips.docs) {
    const members = await t.ref.collection('members').where('uid', '==', uid).get();
    const batch = db.batch();
    members.docs.forEach((m) => batch.update(m.ref, { uid: null }));
    batch.update(t.ref, { memberUids: admin.firestore.FieldValue.arrayRemove(uid) });
    await batch.commit();
    const left = (t.data().memberUids || []).filter((u) => u !== uid);
    if (!left.length) await t.ref.delete(); // tripkhataTripDeleted cleans up the rest
  }
  logger.info('account deleted', { uid, trips: trips.size });
});

/**
 * Signed R2 URLs for trip photos. Only people in the trip get them.
 * Upload URLs are tied to the exact file size and image/jpeg, so a URL can't
 * be reused for something bigger.
 */
exports.tripkhataPhotoUrls = onCall(
  { region: FIRESTORE_REGION, secrets: R2_SECRETS, memory: '256MiB', maxInstances: 5 },
  async (req) => {
    if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in to see trip photos.');
    let plan;
    try {
      plan = photos.planRequest(req.data);
    } catch (e) {
      throw new HttpsError('invalid-argument', e.message);
    }
    const trip = await admin.firestore().collection(TRIPS).doc(plan.tripId).get();
    if (!trip.exists || !(trip.data().memberUids || []).includes(req.auth.uid)) {
      throw new HttpsError('permission-denied', 'You are not in this trip.');
    }
    const Bucket = R2_BUCKET.value();
    const opts = { expiresIn: photos.URL_TTL_SECONDS };
    const uploads = {};
    for (const p of plan.puts) {
      const url = await getSignedUrl(
        r2(),
        new PutObjectCommand({ Bucket, Key: p.key, ContentType: 'image/jpeg', ContentLength: p.bytes }),
        { ...opts, signableHeaders: new Set(['content-type', 'content-length']) },
      );
      uploads[p.id] = { ...(uploads[p.id] || {}), [p.kind]: url, key: photos.fullKey(plan.tripId, p.id) };
    }
    const downloads = {};
    for (const key of plan.gets) {
      downloads[key] = await getSignedUrl(r2(), new GetObjectCommand({ Bucket, Key: key }), opts);
    }
    return { uploads, downloads };
  },
);

/** A photo was deleted from a trip: remove the files from R2. */
exports.tripkhataPhotoDeleted = onDocumentDeleted(
  { document: `${TRIPS}/{tripId}/photos/{photoId}`, region: FIRESTORE_REGION, secrets: R2_SECRETS },
  async (event) => {
    const { tripId, photoId } = event.params;
    await deleteR2([photos.fullKey(tripId, photoId), photos.thumbKey(tripId, photoId)]);
    logger.info('photo deleted', { tripId, photoId });
  },
);
