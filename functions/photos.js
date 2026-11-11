// Trip photos live in Cloudflare R2 (10 GB, 1M uploads and 10M reads a month
// free, no download fees). The bucket is private: the app asks the callable
// function for short-lived signed URLs, and only people in the trip get them.
//
// Keys: tripkhata/{tripId}/photos/{photoId}.jpg       compressed photo
//       tripkhata/{tripId}/photos/{photoId}_t.jpg     thumbnail for the grid

const ROOT = 'tripkhata';
const ID = /^[A-Za-z0-9_-]{8,64}$/;

/** Biggest files the app sends: ~2048px at quality 80, and a ~480px thumbnail. */
const MAX_FULL_BYTES = 4 * 1024 * 1024;
const MAX_THUMB_BYTES = 400 * 1024;
const MAX_UPLOADS = 20;
const MAX_DOWNLOADS = 100;
const URL_TTL_SECONDS = 15 * 60;

const prefix = (tripId) => `${ROOT}/${tripId}/photos/`;
const fullKey = (tripId, photoId) => `${prefix(tripId)}${photoId}.jpg`;
const thumbKey = (tripId, photoId) => `${prefix(tripId)}${photoId}_t.jpg`;

function isId(v) {
  return typeof v === 'string' && ID.test(v);
}

/** A key that belongs to this trip's photos (no "..", no other trips). */
function isTripPhotoKey(tripId, key) {
  if (typeof key !== 'string' || !key.startsWith(prefix(tripId))) return false;
  return /^[A-Za-z0-9_-]{8,64}(_t)?\.jpg$/.test(key.slice(prefix(tripId).length));
}

function isSize(v, max) {
  return Number.isInteger(v) && v > 0 && v <= max;
}

/**
 * Checks a request and returns what to sign, or throws an Error whose
 * message is safe to show. Pure, so it is unit tested without R2.
 *   uploads:   [{ id, bytes, thumbBytes }]
 *   downloads: [key]
 */
function planRequest(data) {
  const tripId = data && data.tripId;
  if (!isId(tripId)) throw new Error('bad-trip');
  const uploads = Array.isArray(data.uploads) ? data.uploads : [];
  const downloads = Array.isArray(data.downloads) ? data.downloads : [];
  if (uploads.length > MAX_UPLOADS || downloads.length > MAX_DOWNLOADS) throw new Error('too-many');

  const puts = [];
  for (const u of uploads) {
    if (!u || !isId(u.id)) throw new Error('bad-photo');
    if (!isSize(u.bytes, MAX_FULL_BYTES) || !isSize(u.thumbBytes, MAX_THUMB_BYTES)) throw new Error('too-big');
    puts.push({ id: u.id, kind: 'full', key: fullKey(tripId, u.id), bytes: u.bytes });
    puts.push({ id: u.id, kind: 'thumb', key: thumbKey(tripId, u.id), bytes: u.thumbBytes });
  }
  const gets = [...new Set(downloads)];
  for (const k of gets) {
    if (!isTripPhotoKey(tripId, k)) throw new Error('bad-key');
  }
  return { tripId, puts, gets };
}

module.exports = {
  ROOT,
  MAX_FULL_BYTES,
  MAX_THUMB_BYTES,
  URL_TTL_SECONDS,
  prefix,
  fullKey,
  thumbKey,
  isTripPhotoKey,
  planRequest,
};
