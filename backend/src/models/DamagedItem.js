const { db } = require('../config/firebase');

class DamagedItem {
  /**
   * Create a damaged item record
   */
  static async create(record) {
    try {
      const ref = db.collection('damaged_items').doc();
      const payload = {
        ...record,
        createdAt: new Date(),
      };
      await ref.set(payload);
      return { id: ref.id, ...payload };
    } catch (error) {
      throw error;
    }
  }

  /**
   * Get damaged items for an eatery
   */
  static async getByEatery(eateryId) {
    try {
      const snapshot = await db
        .collection('damaged_items')
        .where('eateryId', '==', eateryId)
        .orderBy('createdAt', 'desc')
        .get();
      return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      throw error;
    }
  }
}

module.exports = DamagedItem;
