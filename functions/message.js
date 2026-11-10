// Pure helpers for the expense push (no Firebase imports, so they can be unit tested).

/** 150000 paise -> "₹1,500", 150050 -> "₹1,500.50" (same as the app). */
function formatPaise(paise) {
  const abs = Math.abs(Math.trunc(paise || 0));
  const rupees = Math.floor(abs / 100);
  const p = abs % 100;
  const body = rupees.toLocaleString('en-IN') + (p ? '.' + String(p).padStart(2, '0') : '');
  return (paise < 0 ? '−' : '') + '₹' + body;
}

/**
 * What changed, from the expense doc before and after the write.
 * Returns 'added' | 'edited' | 'deleted' | null (null = nothing to tell anyone).
 */
function changeKind(before, after) {
  if (!after || !after.editedBy) return null; // hard delete, or the initial upload of a shared trip
  if (!before) return after.deleted ? null : 'added';
  if (after.deleted) return before.deleted ? null : 'deleted';
  if (before.deleted) return 'added'; // brought back
  if (before.updatedAt === after.updatedAt) return null; // same edit pushed again
  return 'edited';
}

/** Title and body for one recipient. `myShare` is null when they aren't a member row we can match. */
function buildMessage({ kind, author, tripName, title, amount, myShare }) {
  const what = title || 'an expense';
  if (kind === 'deleted') {
    return { title: `${author} deleted ${what}`, body: tripName };
  }
  const share = myShare ? `your share ${formatPaise(myShare)}` : 'not in your share';
  return {
    title: kind === 'added' ? `${author} added ${formatPaise(amount)}` : `${author} edited ${what}`,
    body: [what, tripName, share].join(' · '),
  };
}

module.exports = { formatPaise, changeKind, buildMessage };
