/**
 * Format Firestore Timestamp or Date to YYYY-MM-DD string
 */
function formatDate(timestamp) {
  let date;
  if (timestamp && typeof timestamp.toDate === 'function') {
    date = timestamp.toDate();
  } else if (timestamp instanceof Date) {
    date = timestamp;
  } else if (typeof timestamp === 'string') {
    date = new Date(timestamp);
  } else {
    date = new Date();
  }
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * Calculate percentage change between current and previous values
 */
function calculatePercentageChange(current, previous) {
  if (!previous || previous === 0) return 0;
  return Math.round(((current - previous) / previous) * 10000) / 100;
}

/**
 * Round amount to 2 decimal places
 */
function roundAmount(amount) {
  return Math.round((amount + Number.EPSILON) * 100) / 100;
}

module.exports = { formatDate, calculatePercentageChange, roundAmount };
