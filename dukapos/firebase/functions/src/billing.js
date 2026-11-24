const { onRequest, onCall, HttpsError } = require('firebase-functions/v2/https');
const { google } = require('googleapis');
const admin = require('firebase-admin');

const PACKAGE_NAME = process.env.PLAY_PACKAGE_NAME || 'duka.pos';
const GRACE_DAYS = 7;
const PRODUCT_TO_PLAN = {
  starter_monthly: 'starter', starter_annual: 'starter',
  business_monthly: 'business', business_annual: 'business',
  multibranch_monthly: 'multibranch', multibranch_annual: 'multibranch',
};
const fallbackPlans = [
  { plan: 'free', productId: 'free', interval: 'forever', maxUsers: 1, maxBranches: 1, maxProducts: 100, features: { reports: true, offlineSales: true }, displayName: 'Free', description: '1 user · 1 branch · 100 products' },
  { plan: 'starter', productId: 'starter_monthly', interval: 'monthly', maxUsers: 2, maxBranches: 1, maxProducts: 1000, features: { reports: true, customers: true, offlineSales: true }, displayName: 'Starter', description: 'For a growing shop', targetPriceKsh: 300 },
  { plan: 'business', productId: 'business_monthly', interval: 'monthly', maxUsers: 5, maxBranches: 1, maxProducts: 5000, features: { reports: true, customers: true, audit: true, mpesa: true, offlineSales: true }, displayName: 'Business', description: 'Controls for a busy store' },
  { plan: 'multibranch', productId: 'multibranch_monthly', interval: 'monthly', maxUsers: 25, maxBranches: 10, maxProducts: 20000, features: { reports: true, customers: true, audit: true, mpesa: true, multibranch: true, offlineSales: true }, displayName: 'Multi-branch', description: 'Central visibility across branches' },
];

function publisher() {
  const auth = new google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  return google.androidpublisher({ version: 'v3', auth });
}

async function requireAuth(req) {
  const value = req.headers.authorization || '';
  if (!value.startsWith('Bearer ')) throw new Error('Missing Firebase ID token');
  return admin.auth().verifyIdToken(value.substring(7));
}

async function getCatalog() {
  const snapshot = await admin.firestore().collection('billingPlans').where('active', '==', true).get();
  if (snapshot.empty) return fallbackPlans;
  return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

function subscriptionState(resource) {
  const state = resource.subscriptionState || '';
  if (state.endsWith('ACTIVE')) return 'active';
  if (state.endsWith('IN_GRACE_PERIOD')) return 'grace_period';
  if (state.endsWith('ON_HOLD')) return 'account_hold';
  if (state.endsWith('PENDING')) return 'pending';
  if (state.endsWith('CANCELED')) return 'canceled';
  if (state.endsWith('EXPIRED')) return 'expired';
  return 'unknown';
}

async function verifyAndPersist({ businessId, productId, purchaseToken, uid, source = 'server' }) {
  if (!PRODUCT_TO_PLAN[productId]) throw new Error('Unknown subscription product');
  const api = publisher();
  const result = await api.purchases.subscriptionsv2.get({ packageName: PACKAGE_NAME, token: purchaseToken });
  const resource = result.data;
  const item = (resource.lineItems || []).find((line) => line.productId === productId) || resource.lineItems?.[0];
  const status = subscriptionState(resource);
  const expiry = item?.expiryTime || null;
  const entitlement = {
    plan: PRODUCT_TO_PLAN[productId], productId, status,
    expiresAt: expiry, lastVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    source, purchaseTokenHash: require('crypto').createHash('sha256').update(purchaseToken).digest('hex'),
    linkedPurchaseToken: resource.linkedPurchaseToken || null,
  };
  const db = admin.firestore();
  await db.collection('billingTokens').doc(require('crypto').createHash('sha256').update(purchaseToken).digest('hex')).set({ businessId, productId, uid, purchaseToken, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  await db.collection('businesses').doc(businessId).set({ billing: entitlement }, { merge: true });
  // Acknowledge only verified completed purchases. Do not acknowledge pending/invalid tokens.
  if (resource.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING' && status !== 'pending') {
    await api.purchases.subscriptions.acknowledge({ packageName: PACKAGE_NAME, subscriptionId: productId, token: purchaseToken, requestBody: { developerPayload: 'dukapos-server-verified' } });
  }
  return { plan: entitlement.plan, status, expiresAt: expiry, lastVerifiedAt: new Date().toISOString(), productId };
}

exports.billingCatalog = onRequest(async (req, res) => {
  if (req.method !== 'GET') return res.status(405).json({ error: 'GET required' });
  return res.json({ plans: await getCatalog() });
});

exports.billingVerify = onRequest(async (req, res) => {
  try {
    const decoded = await requireAuth(req);
    const { businessId, productId, purchaseToken } = req.body || {};
    if (!businessId || !productId || !purchaseToken) return res.status(400).json({ error: 'businessId, productId and purchaseToken are required' });
    // TODO: verify decoded.uid is a member of businesses/{businessId} before accepting the token.
    return res.json(await verifyAndPersist({ businessId, productId, purchaseToken, uid: decoded.uid }));
  } catch (error) {
    console.error('billingVerify', error);
    return res.status(401).json({ error: 'Purchase could not be verified' });
  }
});

exports.billingRtdn = onRequest(async (req, res) => {
  try {
    const message = req.body?.message;
    const messageId = message?.messageId;
    if (!message?.data || !messageId) return res.status(400).send('Invalid Pub/Sub push');
    const db = admin.firestore();
    const eventRef = db.collection('billingRtdn').doc(messageId);
    if ((await eventRef.get()).exists) return res.status(204).send('Duplicate');
    const notification = JSON.parse(Buffer.from(message.data, 'base64').toString('utf8'));
    const sub = notification.subscriptionNotification;
    await eventRef.set({ receivedAt: admin.firestore.FieldValue.serverTimestamp(), notification });
    if (!sub?.purchaseToken) return res.status(204).send('Ignored');
    const hash = require('crypto').createHash('sha256').update(sub.purchaseToken).digest('hex');
    const tokenDoc = await db.collection('billingTokens').doc(hash).get();
    if (!tokenDoc.exists) return res.status(204).send('Token not linked');
    const data = tokenDoc.data();
    await verifyAndPersist({ businessId: data.businessId, productId: data.productId, purchaseToken: sub.purchaseToken, uid: data.uid, source: 'rtdn' });
    return res.status(204).send('Processed');
  } catch (error) {
    console.error('billingRtdn', error);
    return res.status(500).send('Retry');
  }
});

exports.setBillingOverride = onCall(async (request) => {
  if (!request.auth?.token?.admin) throw new HttpsError('permission-denied', 'Admin claim required');
  const { businessId, plan, expiresAt, status = 'active', reason } = request.data || {};
  if (!businessId || !plan || !reason) throw new HttpsError('invalid-argument', 'businessId, plan and reason are required');
  await admin.firestore().collection('businesses').doc(businessId).set({ billing: { plan, status, expiresAt: expiresAt || null, source: 'admin_override', override: true, reason, updatedBy: request.auth.uid, updatedAt: admin.firestore.FieldValue.serverTimestamp() } }, { merge: true });
  return { ok: true };
});

exports.listBillingBusinesses = onCall(async (request) => {
  if (!request.auth?.token?.admin) throw new HttpsError('permission-denied', 'Admin claim required');
  const snapshot = await admin.firestore().collection('businesses').select('name', 'billing').limit(500).get();
  return { businesses: snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })) };
});
