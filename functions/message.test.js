const test = require('node:test');
const assert = require('node:assert');
const { formatPaise, changeKind, buildMessage } = require('./message');

test('formatPaise', () => {
  assert.strictEqual(formatPaise(150000), '₹1,500');
  assert.strictEqual(formatPaise(15000000), '₹1,50,000');
  assert.strictEqual(formatPaise(150050), '₹1,500.50');
});

test('changeKind', () => {
  const a = { editedBy: 'u1', updatedAt: 1 };
  assert.strictEqual(changeKind(null, a), 'added');
  assert.strictEqual(changeKind(null, { updatedAt: 1 }), null); // initial upload, no author
  assert.strictEqual(changeKind(a, { ...a, updatedAt: 2 }), 'edited');
  assert.strictEqual(changeKind(a, { ...a }), null);
  assert.strictEqual(changeKind(a, { ...a, deleted: true, updatedAt: 2 }), 'deleted');
  assert.strictEqual(changeKind({ ...a, deleted: true }, { ...a, deleted: true, updatedAt: 3 }), null);
  assert.strictEqual(changeKind(a, null), null);
});

test('buildMessage', () => {
  const m = buildMessage({ kind: 'added', author: 'Rahul', tripName: 'Manali', title: 'Petrol', amount: 150000, myShare: 37500 });
  assert.deepStrictEqual(m, { title: 'Rahul added ₹1,500', body: 'Petrol · Manali · your share ₹375' });
  const k = buildMessage({ kind: 'added', author: 'Rahul', tripName: 'Manali', title: 'Keychain', amount: 20000, myShare: 0 });
  assert.strictEqual(k.body, 'Keychain · Manali · not in your share');
  const d = buildMessage({ kind: 'deleted', author: 'Aman', tripName: 'Manali', title: 'Chai' });
  assert.deepStrictEqual(d, { title: 'Aman deleted Chai', body: 'Manali' });
});
