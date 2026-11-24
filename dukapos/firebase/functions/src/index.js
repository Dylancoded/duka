// Production scaffold: install firebase-functions, firebase-admin and axios in this folder before deploy.
// Keep Daraja credentials in Secret Manager. The mobile app must never call this function with credentials.
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');

admin.initializeApp();
const DARAJA_CALLBACK_AUDIT_KEY = defineSecret('DARAJA_CALLBACK_AUDIT_KEY');

exports.darajaCallback = onRequest({ secrets: [DARAJA_CALLBACK_AUDIT_KEY] }, async (req, res) => {
  // TODO: validate a signed callback envelope at the gateway if enabled, then persist the raw
  // callback and idempotently update businesses/{businessId}/sales/{saleId}/payments/{paymentId}.
  // Only mark a payment confirmed when ResultCode === 0 and the CheckoutRequestID matches a
  // pending payment created by this system. Never trust amount/phone/reference from the client.
  const callback = req.body || {};
  const result = callback?.Body?.stkCallback;
  if (!result) return res.status(400).json({ ok: false, error: 'Invalid Daraja callback' });
  await admin.firestore().collection('darajaCallbacks').add({ receivedAt: admin.firestore.FieldValue.serverTimestamp(), resultCode: result.ResultCode, checkoutRequestId: result.CheckoutRequestID, raw: callback });
  return res.status(200).json({ ok: true });
});

Object.assign(exports, require('./billing'));
