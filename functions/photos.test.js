const test = require('node:test');
const assert = require('node:assert');
const { planRequest, isTripPhotoKey, fullKey, thumbKey } = require('./photos');

const trip = '0b6f2c1e-1111-4a2b-9c3d-123456789abc';
const photo = '7d1e2f3a-2222-4b5c-8d9e-abcdefabcdef';

test('upload plan signs a photo and its thumbnail at their sizes', () => {
  const plan = planRequest({ tripId: trip, uploads: [{ id: photo, bytes: 350000, thumbBytes: 30000 }] });
  assert.deepStrictEqual(plan.puts.map((p) => [p.kind, p.key, p.bytes]), [
    ['full', `tripkhata/${trip}/photos/${photo}.jpg`, 350000],
    ['thumb', `tripkhata/${trip}/photos/${photo}_t.jpg`, 30000],
  ]);
});

test('rejects bad trips, ids, sizes and counts', () => {
  assert.throws(() => planRequest({ tripId: '../x' }), /bad-trip/);
  assert.throws(() => planRequest({ tripId: trip, uploads: [{ id: 'a/b', bytes: 1, thumbBytes: 1 }] }), /bad-photo/);
  assert.throws(() => planRequest({ tripId: trip, uploads: [{ id: photo, bytes: 9e6, thumbBytes: 1 }] }), /too-big/);
  assert.throws(() => planRequest({ tripId: trip, uploads: [{ id: photo, bytes: 0, thumbBytes: 1 }] }), /too-big/);
  const many = Array.from({ length: 21 }, () => ({ id: photo, bytes: 1, thumbBytes: 1 }));
  assert.throws(() => planRequest({ tripId: trip, uploads: many }), /too-many/);
});

test('downloads only keys of this trip', () => {
  assert.ok(isTripPhotoKey(trip, fullKey(trip, photo)));
  assert.ok(isTripPhotoKey(trip, thumbKey(trip, photo)));
  assert.ok(!isTripPhotoKey(trip, `tripkhata/${trip}/photos/../bills/x.jpg`));
  assert.ok(!isTripPhotoKey(trip, fullKey('another-trip-id', photo)));
  assert.throws(() => planRequest({ tripId: trip, downloads: [fullKey('another-trip-id', photo)] }), /bad-key/);
  const plan = planRequest({ tripId: trip, downloads: [fullKey(trip, photo), fullKey(trip, photo)] });
  assert.strictEqual(plan.gets.length, 1);
});
