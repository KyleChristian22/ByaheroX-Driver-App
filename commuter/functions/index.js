/**
 * Firebase Cloud Functions owned by the ByaheroX Commuter app.
 *
 * Commuter login/register stays direct Firebase Auth. This backend only handles
 * commuter-specific sensitive checks that the client should not decide alone.
 *
 * Current payment model:
 *   1. AI-scanned GCash receipt top-ups for commuters.
 *   2. Cash payout requests for driver earnings.
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");

require("dotenv").config();

admin.initializeApp();

const db = admin.firestore();
// ---------------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------------

function receiptConfig() {
  const openaiConfig = functions.config().openai || {};
  const gcashConfig = functions.config().gcash || {};
  return {
    openaiApiKey: process.env.OPENAI_API_KEY || openaiConfig.api_key || "",
    coopGcashName: process.env.COOP_GCASH_NAME || gcashConfig.account_name || "",
    coopGcashNumber: process.env.COOP_GCASH_NUMBER || gcashConfig.account_number || "",
    storageBucket: process.env.FIREBASE_STORAGE_BUCKET || gcashConfig.storage_bucket || "",
    receiptMaxAgeDays: Number(
      process.env.RECEIPT_MAX_AGE_DAYS || gcashConfig.receipt_max_age_days || 3
    ),
  };
}

async function verifyAuthToken(req) {
  const authHeader = req.get("Authorization") || "";
  const match = authHeader.match(/^Bearer (.+)$/);
  if (!match) {
    return null;
  }
  try {
    return await admin.auth().verifyIdToken(match[1]);
  } catch {
    return null;
  }
}

function normalizeEmail(email) {
  return (email || "").toString().trim().toLowerCase();
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function setCorsHeaders(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Max-Age", "3600");
}

function handleOptionsRequest(req, res) {
  if (req.method === "OPTIONS") {
    setCorsHeaders(res);
    res.status(204).send("");
    return true;
  }
  return false;
}

function normalizePhone(value) {
  const digits = (value || "").toString().replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("63")) return digits;
  if (digits.startsWith("0")) return `63${digits.slice(1)}`;
  if (digits.length === 10 && digits.startsWith("9")) return `63${digits}`;
  return digits;
}

function normalizeReference(value) {
  return (value || "").toString().replace(/\D/g, "");
}

function hasMaskedCharacters(value) {
  return /[\u2022\u25cf*xX]/.test((value || "").toString());
}

function receiverNumberMatch(extractedValue, expectedValue) {
  const raw = (extractedValue || "").toString().trim();
  const expectedDigits = normalizePhone(expectedValue);
  const extractedDigits = normalizePhone(raw);

  if (!expectedDigits) {
    return {
      matches: false,
      normalized: extractedDigits,
      matchType: "missing_expected",
    };
  }

  if (extractedDigits === expectedDigits) {
    return {
      matches: true,
      normalized: extractedDigits,
      matchType: "exact",
    };
  }

  if (!hasMaskedCharacters(raw)) {
    return {
      matches: false,
      normalized: extractedDigits,
      matchType: "mismatch",
    };
  }

  const maskMatch = raw.match(/[\u2022\u25cf*xX]+/);
  const firstMaskIndex = maskMatch ? maskMatch.index : -1;
  const lastMaskIndex = firstMaskIndex >= 0 ?
    firstMaskIndex + maskMatch[0].length :
    -1;
  const visiblePrefix = firstMaskIndex >= 0 ?
    normalizePhone(raw.slice(0, firstMaskIndex)) :
    "";
  const visibleSuffix = lastMaskIndex >= 0 ?
    normalizePhone(raw.slice(lastMaskIndex)) :
    "";
  const visibleGroups = raw.match(/\d+/g) || [];
  let searchFrom = 0;
  const groupsMatchInOrder = visibleGroups.every((group) => {
    const foundAt = expectedDigits.indexOf(group, searchFrom);
    if (foundAt < 0) return false;
    searchFrom = foundAt + group.length;
    return true;
  });
  const prefixMatches = visiblePrefix.length >= 3 &&
    expectedDigits.startsWith(visiblePrefix);
  const suffixMatches = visibleSuffix.length >= 4 &&
    expectedDigits.endsWith(visibleSuffix);

  return {
    matches: prefixMatches && suffixMatches && groupsMatchInOrder,
    normalized: extractedDigits,
    matchType: "masked",
  };
}

function normalizeAmount(value) {
  if (typeof value === "number") return value;
  const parsed = Number((value || "").toString().replace(/[^\d.]/g, ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

function hasSentViaGcashText(value) {
  return /sent\s+via\s+gcash/i.test((value || "").toString());
}

function parseReceiptImage(receiptImageBase64, mimeType) {
  if (!receiptImageBase64 || typeof receiptImageBase64 !== "string") {
    throw new Error("Receipt image is required");
  }

  const dataUrlMatch = receiptImageBase64.match(/^data:([^;]+);base64,(.+)$/);
  const resolvedMimeType = dataUrlMatch ? dataUrlMatch[1] : (mimeType || "image/jpeg");
  const rawBase64 = dataUrlMatch ? dataUrlMatch[2] : receiptImageBase64;
  const bytes = Buffer.from(rawBase64, "base64");

  if (!bytes.length) {
    throw new Error("Receipt image is empty");
  }

  const maxBytes = 5 * 1024 * 1024;
  if (bytes.length > maxBytes) {
    throw new Error("Receipt image must be 5MB or smaller");
  }

  return {
    bytes,
    mimeType: resolvedMimeType,
    dataUrl: `data:${resolvedMimeType};base64,${rawBase64}`,
    sha256: crypto.createHash("sha256").update(bytes).digest("hex"),
  };
}

function toTimestampOrNull(value) {
  if (!value) return null;
  const parsed = parsePhilippineReceiptDate(value);
  return Number.isNaN(parsed.getTime()) ?
    null :
    admin.firestore.Timestamp.fromDate(parsed);
}

function parsePhilippineReceiptDate(value) {
  const text = (value || "").toString().trim();
  if (!text) return new Date("invalid");
  const hasTimezone = /(?:z|[+-]\d{2}:?\d{2})$/i.test(text);
  if (hasTimezone) return new Date(text);

  const isoLike = text.match(
    /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?)$/
  );
  if (isoLike) {
    return new Date(`${isoLike[1]}T${isoLike[2]}+08:00`);
  }

  return new Date(`${text} GMT+0800`);
}

function isBlockedCommuterRole(role) {
  const normalizedRole = (role || "").toString().trim().toLowerCase();
  return normalizedRole === "driver" ||
    normalizedRole === "admin" ||
    normalizedRole === "super_admin";
}

function isBlockedCommuterStatus(status) {
  const normalizedStatus = (status || "").toString().trim().toLowerCase();
  return normalizedStatus === "blocked" || normalizedStatus === "suspended";
}

async function driverAccountExistsForEmailOrUid(email, uid) {
  const queries = [
    db.collection("driver").where("email", "==", email).limit(1).get(),
  ];

  if (uid) {
    queries.push(
      db.collection("driver").where("uid", "==", uid).limit(1).get(),
      db.collection("driver").where("firebaseUid", "==", uid).limit(1).get(),
      db.collection("driver").doc(uid).get(),
    );
  }

  const snapshots = await Promise.all(queries);
  return snapshots.some((snapshot) => {
    if (typeof snapshot.exists === "boolean") {
      return snapshot.exists;
    }
    return !snapshot.empty;
  });
}

async function getCommuterDocForEmailOrUid(email, uid) {
  if (uid) {
    const doc = await db.collection("commuters").doc(uid).get();
    if (doc.exists) {
      return doc;
    }
  }

  const snapshot = await db.collection("commuters")
    .where("email", "==", email)
    .limit(1)
    .get();
  return snapshot.empty ? null : snapshot.docs[0];
}

async function canAccessTreasurer(decodedToken) {
  if (!decodedToken) {
    return false;
  }

  const byUid = await db.collection("treasurer").doc(decodedToken.uid).get();
  if (byUid.exists) {
    const data = byUid.data() || {};
    const role = (data.role || "treasurer").toString().trim().toLowerCase();
    const status = (data.status || "active").toString().trim().toLowerCase();
    return role === "treasurer" && status !== "blocked" && status !== "suspended";
  }

  const email = normalizeEmail(decodedToken.email);
  if (!email) {
    return false;
  }

  const byEmail = await db.collection("treasurer")
    .where("email", "==", email)
    .limit(1)
    .get();

  if (byEmail.empty) {
    return false;
  }

  const data = byEmail.docs[0].data() || {};
  const role = (data.role || "treasurer").toString().trim().toLowerCase();
  const status = (data.status || "active").toString().trim().toLowerCase();
  return role === "treasurer" && status !== "blocked" && status !== "suspended";
}

async function canAccessDriver(decodedToken, driverId) {
  if (!decodedToken || !driverId) {
    return false;
  }

  if (decodedToken.uid === driverId) {
    return true;
  }

  const driverDoc = await db.collection("driver").doc(driverId).get();
  if (driverDoc.exists) {
    const data = driverDoc.data() || {};
    return data.uid === decodedToken.uid || data.firebaseUid === decodedToken.uid;
  }

  const email = normalizeEmail(decodedToken.email);
  if (!email) {
    return false;
  }

  const byEmail = await db.collection("driver")
    .where("email", "==", email)
    .limit(1)
    .get();

  if (byEmail.empty) {
    return false;
  }

  return byEmail.docs[0].id === driverId;
}

function rejectCommuterNotFound(res) {
  res.status(404).json({
    success: false,
    errorCode: "commuter-not-found",
    message: "No active commuter account found for this email",
  });
}

// ---------------------------------------------------------------------------
// COMMUTER PASSWORD RESET VALIDATION (existing)
// ---------------------------------------------------------------------------

exports.commuterValidatePasswordReset = functions.https.onRequest(async (req, res) => {
  setCorsHeaders(res);
  if (handleOptionsRequest(req, res)) {
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({success: false, message: "Method not allowed"});
    return;
  }

  try {
    const email = normalizeEmail(req.body.email);
    if (!isValidEmail(email)) {
      res.status(400).json({
        success: false,
        errorCode: "invalid-email",
        message: "Invalid email format",
      });
      return;
    }

    let authUser = null;
    try {
      authUser = await admin.auth().getUserByEmail(email);
    } catch (error) {
      if (error.code !== "auth/user-not-found") {
        throw error;
      }
    }

    if (await driverAccountExistsForEmailOrUid(email, authUser && authUser.uid)) {
      rejectCommuterNotFound(res);
      return;
    }

    const commuterDoc = await getCommuterDocForEmailOrUid(email, authUser && authUser.uid);
    if (!authUser || !commuterDoc) {
      rejectCommuterNotFound(res);
      return;
    }

    const commuterData = commuterDoc.data() || {};
    if (
      isBlockedCommuterRole(commuterData.role) ||
      isBlockedCommuterStatus(commuterData.status)
    ) {
      rejectCommuterNotFound(res);
      return;
    }

    res.status(200).json({success: true});
  } catch (error) {
    console.error("commuterValidatePasswordReset error:", error);
    res.status(500).json({
      success: false,
      errorCode: "internal",
      message: "Failed to validate password reset request",
    });
  }
});

// ===========================================================================
// AI GCASH RECEIPT TOP-UP
// ===========================================================================

exports.previewGcashReceiptTopup = functions
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onRequest(async (req, res) => {
    setCorsHeaders(res);
    if (handleOptionsRequest(req, res)) return;

    if (req.method !== "POST") {
      res.status(405).json({ success: false, message: "Method not allowed" });
      return;
    }

    try {
      const decoded = await verifyAuthToken(req);
      if (!decoded) {
        res.status(401).json({ success: false, message: "Unauthorized" });
        return;
      }

      const commuterId = req.body.commuterId;
      const { receiptImageBase64, mimeType } = req.body;

      if (!commuterId || decoded.uid !== commuterId) {
        res.status(403).json({ success: false, message: "Commuter ID mismatch" });
        return;
      }

      const receiptImage = parseReceiptImage(receiptImageBase64, mimeType);
      const extraction = await extractGcashReceipt(receiptImage.dataUrl);
      const validation = validateGcashReceipt(extraction, receiptImage.sha256);

      res.status(200).json({
        success: true,
        extracted: extraction,
        aiDecision: validation.decision,
        validationErrors: validation.errors,
        pointsToCredit: validation.pointsToCredit,
        receiptImageHash: receiptImage.sha256,
      });
    } catch (error) {
      console.error("previewGcashReceiptTopup error:", error);
      res.status(error.httpStatus || 500).json({
        success: false,
        retryable: true,
        errorCode: error.code || "receipt_preview_failed",
        message: error.publicMessage || error.message || "Failed to preview GCash receipt",
      });
    }
  });

exports.analyzeGcashReceiptTopup = functions
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .https.onRequest(async (req, res) => {
    setCorsHeaders(res);
    if (handleOptionsRequest(req, res)) return;

    if (req.method !== "POST") {
      res.status(405).json({ success: false, message: "Method not allowed" });
      return;
    }

    let commuterId = null;
    let rfidCard = null;
    let receiptImage = null;

    try {
      const decoded = await verifyAuthToken(req);
      if (!decoded) {
        res.status(401).json({ success: false, message: "Unauthorized" });
        return;
      }

      commuterId = req.body.commuterId;
      rfidCard = req.body.rfidCard;
      const { receiptImageBase64, mimeType } = req.body;

      if (!commuterId || decoded.uid !== commuterId) {
        res.status(403).json({ success: false, message: "Commuter ID mismatch" });
        return;
      }

      receiptImage = parseReceiptImage(receiptImageBase64, mimeType);
      const extraction =
        normalizeConfirmedExtraction(req.body.confirmedExtraction) ||
        await extractGcashReceipt(receiptImage.dataUrl);
      const validation = validateGcashReceipt(extraction, receiptImage.sha256);
      const result = await saveReceiptTopup({
        commuterId,
        rfidCard,
        receiptImageBytes: receiptImage.bytes,
        receiptImageHash: receiptImage.sha256,
        receiptMimeType: receiptImage.mimeType,
        extraction,
        validation,
      });

      res.status(200).json({
        success: true,
        topupRequestId: result.topupRequestId,
        transactionId: result.transactionId,
        status: result.status,
        aiDecision: validation.decision,
        extracted: extraction,
        validationErrors: result.validationErrors,
      });
    } catch (error) {
      console.error("analyzeGcashReceiptTopup error:", error);
      res.status(error.httpStatus || 500).json({
        success: false,
        retryable: error.retryable !== false,
        errorCode: error.code || "receipt_analysis_failed",
        message: error.publicMessage || error.message || "Failed to analyze GCash receipt",
        topupRequestId: null,
        transactionId: null,
      });
    }
  });

function isCancellableTopupStatus(status) {
  const normalized = (status || "").toString().trim().toLowerCase();
  return normalized === "needs_review" ||
    normalized === "pending" ||
    normalized === "requested" ||
    normalized === "";
}

exports.cancelCommuterTopupRequest = functions.https.onRequest(async (req, res) => {
  setCorsHeaders(res);
  if (handleOptionsRequest(req, res)) return;

  if (req.method !== "POST") {
    res.status(405).json({ success: false, message: "Method not allowed" });
    return;
  }

  try {
    const decoded = await verifyAuthToken(req);
    if (!decoded) {
      res.status(401).json({ success: false, message: "Unauthorized" });
      return;
    }

    const commuterId = (req.body.commuterId || "").toString().trim();
    const topupRequestId = (req.body.topupRequestId || "").toString().trim();

    if (!commuterId || decoded.uid !== commuterId) {
      res.status(403).json({ success: false, message: "Commuter ID mismatch" });
      return;
    }

    if (!topupRequestId) {
      res.status(400).json({ success: false, message: "Top-up request ID is required" });
      return;
    }

    const topupRef = db.collection("topup_requests").doc(topupRequestId);
    let transactionIds = [];

    await db.runTransaction(async (transaction) => {
      const topupDoc = await transaction.get(topupRef);
      if (!topupDoc.exists) {
        const error = new Error("Top-up request not found");
        error.httpStatus = 404;
        throw error;
      }

      const topup = topupDoc.data() || {};
      if ((topup.commuterId || "").toString().trim() !== commuterId) {
        const error = new Error("Top-up request does not belong to this commuter");
        error.httpStatus = 403;
        throw error;
      }

      const status = (topup.status || "").toString().trim().toLowerCase();
      if (!isCancellableTopupStatus(status)) {
        const error = new Error("Only top-up requests waiting for review can be cancelled");
        error.httpStatus = 409;
        throw error;
      }

      const transactionSnapshot = await transaction.get(
        db.collection("fare_transactions")
          .where("topupRequestId", "==", topupRequestId)
          .where("commuterId", "==", commuterId)
      );

      const referenceNumber = (topup.extractedReference || "").toString().trim();
      const receiptImageHash = (topup.receiptImageHash || "").toString().trim();
      const referenceRef = referenceNumber ?
        db.collection("gcash_references").doc(referenceNumber) :
        null;
      const receiptHashRef = receiptImageHash ?
        db.collection("receipt_hashes").doc(receiptImageHash) :
        null;

      const duplicateDocs = await Promise.all([
        referenceRef ? transaction.get(referenceRef) : Promise.resolve(null),
        receiptHashRef ? transaction.get(receiptHashRef) : Promise.resolve(null),
      ]);

      const cancelledData = {
        status: "commuter_cancelled",
        cancelledBy: "commuter",
        cancelledByCommuterId: commuterId,
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      transaction.set(topupRef, cancelledData, { merge: true });

      transactionIds = transactionSnapshot.docs.map((doc) => doc.id);
      transactionSnapshot.docs.forEach((doc) => {
        transaction.set(doc.ref, {
          ...cancelledData,
          note: "Top-up request cancelled by commuter",
        }, { merge: true });
      });

      if (referenceRef && duplicateDocs[0] && duplicateDocs[0].exists) {
        transaction.set(referenceRef, {
          status: "commuter_cancelled",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      if (receiptHashRef && duplicateDocs[1] && duplicateDocs[1].exists) {
        transaction.set(receiptHashRef, {
          status: "commuter_cancelled",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    });

    res.status(200).json({
      success: true,
      status: "commuter_cancelled",
      topupRequestId,
      transactionIds,
    });
  } catch (error) {
    console.error("cancelCommuterTopupRequest error:", error);
    res.status(error.httpStatus || 500).json({
      success: false,
      retryable: error.httpStatus !== 409,
      errorCode: error.httpStatus === 409 ? "topup_not_cancellable" : "topup_cancel_failed",
      message: error.message || "Failed to cancel top-up request",
    });
  }
});

async function extractGcashReceipt(imageDataUrl) {
  const { openaiApiKey } = receiptConfig();
  if (!openaiApiKey) {
    throw new Error("OPENAI_API_KEY is not configured");
  }

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openaiApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4.1-mini",
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "Extract fields from this Philippine GCash send-money receipt.",
                "Return only what is visible. Do not infer hidden characters.",
                "If the receiver phone number is masked, preserve the mask characters exactly as visible.",
                "Normalize PHP amounts as numbers.",
                "For paidAt, return ISO-8601 with +08:00 Asia/Manila time if the receipt shows no timezone.",
              ].join(" "),
            },
            {
              type: "input_image",
              image_url: imageDataUrl,
            },
          ],
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "gcash_receipt_extraction",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            properties: {
              isGcashReceipt: { type: "boolean" },
              receiptType: { type: ["string", "null"] },
              receiverName: { type: ["string", "null"] },
              receiverNumber: { type: ["string", "null"] },
              channelText: { type: ["string", "null"] },
              currency: { type: ["string", "null"] },
              amount: { type: ["number", "null"] },
              totalAmountSent: { type: ["number", "null"] },
              referenceNumber: { type: ["string", "null"] },
              paidAt: { type: ["string", "null"] },
              carbonSavingsText: { type: ["string", "null"] },
              confidence: { type: "number" },
              notes: { type: ["string", "null"] },
            },
            required: [
              "isGcashReceipt",
              "receiptType",
              "receiverName",
              "receiverNumber",
              "channelText",
              "currency",
              "amount",
              "totalAmountSent",
              "referenceNumber",
              "paidAt",
              "carbonSavingsText",
              "confidence",
              "notes",
            ],
          },
        },
      },
    }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = payload.error?.message || response.statusText;
    const error = new Error(`OpenAI receipt extraction failed: ${message}`);
    const code = payload.error?.code || "";
    if (response.status === 429 || code === "insufficient_quota" || /quota/i.test(message)) {
      error.code = "openai_quota_exceeded";
      error.httpStatus = 503;
      error.publicMessage = "Receipt scanner is temporarily unavailable. Please try again later.";
    }
    throw error;
  }

  const outputText = readOpenAiOutputText(payload);
  if (!outputText) {
    throw new Error("OpenAI receipt extraction returned no text");
  }

  return JSON.parse(outputText);
}

function normalizeConfirmedExtraction(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  return {
    isGcashReceipt: value.isGcashReceipt === true || value.isGcashReceipt === "true",
    receiptType: nullableString(value.receiptType),
    receiverName: nullableString(value.receiverName),
    receiverNumber: nullableString(value.receiverNumber),
    channelText: nullableString(value.channelText),
    currency: nullableString(value.currency),
    amount: nullableNumber(value.amount),
    totalAmountSent: nullableNumber(value.totalAmountSent),
    referenceNumber: nullableString(value.referenceNumber),
    paidAt: nullableString(value.paidAt),
    carbonSavingsText: nullableString(value.carbonSavingsText),
    confidence: nullableNumber(value.confidence) || 1,
    notes: nullableString(value.notes),
  };
}

function nullableString(value) {
  if (value === null || value === undefined) return null;
  const text = value.toString().trim();
  return text || null;
}

function nullableNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function readOpenAiOutputText(payload) {
  if (payload.output_text) return payload.output_text;
  const output = Array.isArray(payload.output) ? payload.output : [];
  for (const item of output) {
    const content = Array.isArray(item.content) ? item.content : [];
    for (const part of content) {
      if (part.type === "output_text" && part.text) {
        return part.text;
      }
    }
  }
  return "";
}

function validateGcashReceipt(extraction, receiptImageHash) {
  const config = receiptConfig();
  const errors = [];
  const amount = normalizeAmount(extraction.totalAmountSent || extraction.amount);
  const baseAmount = normalizeAmount(extraction.amount);
  const totalAmountSent = normalizeAmount(extraction.totalAmountSent);
  const referenceNumber = normalizeReference(extraction.referenceNumber);
  const receiverNumberValidation =
    receiverNumberMatch(extraction.receiverNumber, config.coopGcashNumber);
  const receiverNumber = receiverNumberValidation.normalized;
  const paidAtDate = extraction.paidAt ? parsePhilippineReceiptDate(extraction.paidAt) : null;

  if (!extraction.isGcashReceipt) {
    errors.push("not_gcash_receipt");
  }

  if (extraction.channelText && !hasSentViaGcashText(extraction.channelText)) {
    errors.push("not_sent_via_gcash");
  }

  if (!config.openaiApiKey) {
    errors.push("openai_not_configured");
  }

  if (receiverNumberValidation.matchType === "missing_expected") {
    errors.push("coop_gcash_number_not_configured");
  } else if (!receiverNumberValidation.matches) {
    errors.push("receiver_number_mismatch");
  }

  if (!Number.isFinite(amount) || amount <= 0) {
    errors.push("invalid_amount");
  }

  if (baseAmount > 0 && totalAmountSent > 0 && Math.abs(baseAmount - totalAmountSent) > 0.009) {
    errors.push("amount_total_mismatch");
  }

  if (!referenceNumber) {
    errors.push("missing_reference_number");
  } else if (referenceNumber.length < 10) {
    errors.push("invalid_reference_number");
  }

  if (!receiptImageHash) {
    errors.push("missing_receipt_hash");
  }

  if (!Number.isFinite(extraction.confidence) || extraction.confidence < 0.85) {
    errors.push("low_ai_confidence");
  }

  if (!paidAtDate || Number.isNaN(paidAtDate.getTime())) {
    errors.push("invalid_receipt_date");
  } else {
    const maxAgeDays = Number.isFinite(config.receiptMaxAgeDays) ?
      config.receiptMaxAgeDays :
      3;
    const maxAgeMs = Math.max(maxAgeDays, 1) * 24 * 60 * 60 * 1000;
    if (Date.now() - paidAtDate.getTime() > maxAgeMs) {
      errors.push("receipt_too_old");
    }
    if (paidAtDate.getTime() - Date.now() > 10 * 60 * 1000) {
      errors.push("receipt_date_in_future");
    }
  }

  return {
    decision: "needs_review",
    errors,
    amount,
    pointsToCredit: amount,
    referenceNumber,
    receiverNumber,
    receiverNumberMatchType: receiverNumberValidation.matchType,
    paidAt: paidAtDate,
  };
}

class ReceiptTopupDuplicateError extends Error {
  constructor({ code, message }) {
    super(message);
    this.code = code;
    this.publicMessage = message;
    this.httpStatus = 409;
    this.retryable = false;
  }
}

async function duplicateBlockCode(transaction, doc, duplicateKind) {
  if (!doc || !doc.exists) return null;
  const status = await duplicateMarkerStatus(transaction, doc);

  if (status === "approved" || status === "auto_approved") {
    return duplicateKind === "reference" ?
      "duplicate_approved_reference_number" :
      "duplicate_approved_receipt_image";
  }

  if (status === "needs_review" || status === "pending" || status === "requested" || status === "") {
    return duplicateKind === "reference" ?
      "duplicate_pending_reference_number" :
      "duplicate_pending_receipt_image";
  }

  return null;
}

async function duplicateMarkerStatus(transaction, doc) {
  const data = doc.data() || {};
  const status = (data.status || "").toString().trim().toLowerCase();
  if (status === "approved" || status === "auto_approved" || status === "rejected" || status === "ai_failed") {
    return status;
  }

  const topupRequestId = (data.topupRequestId || "").toString().trim();
  if (topupRequestId) {
    const topupDoc = await transaction.get(db.collection("topup_requests").doc(topupRequestId));
    if (topupDoc.exists) {
      const topupStatus = ((topupDoc.data() || {}).status || "").toString().trim().toLowerCase();
      if (topupStatus) return topupStatus;
    }
  }

  const transactionId = (data.transactionId || "").toString().trim();
  if (transactionId) {
    const fareDoc = await transaction.get(db.collection("fare_transactions").doc(transactionId));
    if (fareDoc.exists) {
      const fareStatus = ((fareDoc.data() || {}).status || "").toString().trim().toLowerCase();
      if (fareStatus) return fareStatus;
    }
  }

  return status;
}

function duplicateBlockMessage(code) {
  switch (code) {
    case "duplicate_approved_reference_number":
      return "This GCash reference number has already been approved for a top-up";
    case "duplicate_approved_receipt_image":
      return "This receipt image has already been approved for a top-up";
    case "duplicate_pending_reference_number":
      return "This GCash reference number is already waiting for treasurer review";
    case "duplicate_pending_receipt_image":
      return "This receipt image is already waiting for treasurer review";
    default:
      return "This receipt has already been submitted";
  }
}

async function saveReceiptTopup({
  commuterId,
  rfidCard,
  receiptImageBytes,
  receiptImageHash,
  receiptMimeType,
  extraction,
  validation,
}) {
  const topupRef = db.collection("topup_requests").doc();
  const transactionRef = db.collection("fare_transactions").doc();
  const referenceRef = validation.referenceNumber ?
    db.collection("gcash_references").doc(validation.referenceNumber) :
    null;
  const receiptHashRef = receiptImageHash ?
    db.collection("receipt_hashes").doc(receiptImageHash) :
    null;
  const walletRef = db.collection("commuter_wallets").doc(commuterId);

  let status = validation.decision;
  let balanceBefore = null;
  let balanceAfter = null;
  let finalValidationErrors = [...validation.errors];
  const receiptImagePath = await uploadReceiptImage({
    commuterId,
    topupRequestId: topupRef.id,
    bytes: receiptImageBytes,
    mimeType: receiptMimeType,
  });

  try {
    await db.runTransaction(async (transaction) => {
      const docsToRead = [
        transaction.get(walletRef),
      ];

      if (referenceRef) docsToRead.push(transaction.get(referenceRef));
      if (receiptHashRef) docsToRead.push(transaction.get(receiptHashRef));

      const snapshots = await Promise.all(docsToRead);
      const walletDoc = snapshots[0];
      const referenceDoc = referenceRef ? snapshots[1] : null;
      const hashDoc = receiptHashRef ? snapshots[snapshots.length - 1] : null;
      const duplicateCodes = (await Promise.all([
        duplicateBlockCode(transaction, referenceDoc, "reference"),
        duplicateBlockCode(transaction, hashDoc, "receipt"),
      ])).filter(Boolean);

      if (duplicateCodes.length) {
        const code = duplicateCodes[0];
        throw new ReceiptTopupDuplicateError({
          code,
          message: duplicateBlockMessage(code),
        });
      }

      const validationErrors = [...validation.errors];
      finalValidationErrors = validationErrors;
      status = "needs_review";
      const requiresReceiptReview = true;

      balanceBefore = walletDoc.exists ? Number(walletDoc.data().balance || 0) : 0;
      balanceAfter = balanceBefore;

      const commonData = {
        commuterId,
        rfidCard: rfidCard || null,
        amountPaid: validation.amount,
        pointsToCredit: validation.pointsToCredit,
        receiptImagePath,
        receiptImageHash,
        extractedReceiptType: extraction.receiptType || null,
        extractedReceiverName: extraction.receiverName || null,
        extractedReceiverNumber: extraction.receiverNumber || null,
        receiverNumberMatchType: validation.receiverNumberMatchType,
        extractedChannelText: extraction.channelText || null,
        extractedCurrency: extraction.currency || null,
        extractedAmount: extraction.amount || null,
        extractedTotalAmountSent: extraction.totalAmountSent || null,
        extractedReference: validation.referenceNumber || null,
        extractedPaidAt: toTimestampOrNull(extraction.paidAt),
        extractedCarbonSavingsText: extraction.carbonSavingsText || null,
        aiConfidence: extraction.confidence,
        aiDecision: status,
        validationErrors,
        requiresReceiptReview,
        creditMode: "receipt_review",
        status,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      transaction.set(topupRef, {
        ...commonData,
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        approvedAt: null,
      });

      transaction.set(transactionRef, {
        type: "regular_gcash_topup",
        paymentMethod: "ai_gcash_receipt",
        status,
        commuterId,
        rfidCard: rfidCard || null,
        amount: validation.amount,
        points: validation.pointsToCredit,
        gcashReference: validation.referenceNumber || null,
        receiptType: extraction.receiptType || null,
        gcashReceiverName: extraction.receiverName || null,
        gcashReceiverNumber: extraction.receiverNumber || null,
        receiverNumberMatchType: validation.receiverNumberMatchType,
        gcashChannelText: extraction.channelText || null,
        currency: extraction.currency || null,
        extractedAmount: extraction.amount || null,
        extractedTotalAmountSent: extraction.totalAmountSent || null,
        extractedPaidAt: toTimestampOrNull(extraction.paidAt),
        carbonSavingsText: extraction.carbonSavingsText || null,
        topupRequestId: topupRef.id,
        receiptImagePath,
        receiptImageHash,
        aiConfidence: extraction.confidence,
        validationErrors,
        requiresReceiptReview,
        creditMode: "receipt_review",
        balanceBefore,
        balanceAfter,
        processedBy: "ai_receipt_scanner",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      if (referenceRef) {
        transaction.set(referenceRef, {
          topupRequestId: topupRef.id,
          transactionId: transactionRef.id,
          commuterId,
          amount: validation.amount,
          status,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      if (receiptHashRef) {
        transaction.set(receiptHashRef, {
          topupRequestId: topupRef.id,
          transactionId: transactionRef.id,
          commuterId,
          status,
          uploadedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });
  } catch (txError) {
    await deleteGcsFile(receiptImagePath);
    throw txError;
  }

  return {
    topupRequestId: topupRef.id,
    transactionId: transactionRef.id,
    status,
    validationErrors: finalValidationErrors,
  };
}

async function uploadReceiptImage({ commuterId, topupRequestId, bytes, mimeType }) {
  const extensionByMime = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
  };
  const extension = extensionByMime[mimeType] || "jpg";
  const path = `gcash_receipts/${commuterId}/${topupRequestId}.${extension}`;
  const { storageBucket } = receiptConfig();
  const bucket = storageBucket ?
    admin.storage().bucket(storageBucket) :
    admin.storage().bucket();
  const file = bucket.file(path);

  await file.save(bytes, {
    resumable: false,
    metadata: {
      contentType: mimeType,
      metadata: {
        commuterId,
        topupRequestId,
      },
    },
  });

  return path;
}

async function deleteGcsFile(filePath) {
  if (!filePath) return;
  try {
    const { storageBucket } = receiptConfig();
    const bucket = storageBucket ?
      admin.storage().bucket(storageBucket) :
      admin.storage().bucket();
    await bucket.file(filePath).delete({ ignoreNotFound: true });
  } catch (cleanupError) {
    console.error("Failed to clean up GCS file:", filePath, cleanupError);
  }
}

// ===========================================================================
// DRIVER CASH PAYOUTS (Cash payout by Treasurer)
// ===========================================================================

exports.requestDriverCashPayout = functions.https.onRequest(async (req, res) => {
  setCorsHeaders(res);
  if (handleOptionsRequest(req, res)) return;

  if (req.method !== "POST") {
    res.status(405).json({ success: false, message: "Method not allowed" });
    return;
  }

  try {
    const decoded = await verifyAuthToken(req);
    const driverId = (req.body.driverId || "").toString().trim();
    if (!(await canAccessDriver(decoded, driverId))) {
      res.status(403).json({ success: false, message: "Driver access required" });
      return;
    }

    const amount = Number(req.body.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      res.status(400).json({ success: false, message: "Invalid payout amount" });
      return;
    }

    const result = await createDriverPayoutRequest({
      driverId,
      amount,
    });

    res.status(200).json({ success: true, ...result });
  } catch (error) {
    console.error("requestDriverCashPayout error:", error);
    res.status(500).json({
      success: false,
      message: error.message || "Failed to request driver payout",
    });
  }
});

exports.markDriverPayoutPaid = functions.https.onRequest(async (req, res) => {
  setCorsHeaders(res);
  if (handleOptionsRequest(req, res)) return;

  if (req.method !== "POST") {
    res.status(405).json({ success: false, message: "Method not allowed" });
    return;
  }

  try {
    const decoded = await verifyAuthToken(req);
    if (!(await canAccessTreasurer(decoded))) {
      res.status(403).json({ success: false, message: "Treasurer access required" });
      return;
    }

    const payoutId = (req.body.payoutId || "").toString().trim();
    if (!payoutId) {
      res.status(400).json({ success: false, message: "Payout ID is required" });
      return;
    }

    await updateDriverPayoutStatus({
      payoutId,
      status: "paid",
      treasurerUid: decoded.uid,
      rejectionReason: "",
    });

    res.status(200).json({ success: true, status: "paid" });
  } catch (error) {
    console.error("markDriverPayoutPaid error:", error);
    res.status(500).json({
      success: false,
      message: error.message || "Failed to mark driver payout paid",
    });
  }
});

exports.rejectDriverPayout = functions.https.onRequest(async (req, res) => {
  setCorsHeaders(res);
  if (handleOptionsRequest(req, res)) return;

  if (req.method !== "POST") {
    res.status(405).json({ success: false, message: "Method not allowed" });
    return;
  }

  try {
    const decoded = await verifyAuthToken(req);
    if (!(await canAccessTreasurer(decoded))) {
      res.status(403).json({ success: false, message: "Treasurer access required" });
      return;
    }

    const payoutId = (req.body.payoutId || "").toString().trim();
    const rejectionReason = (req.body.rejectionReason || "").toString().trim();
    if (!payoutId) {
      res.status(400).json({ success: false, message: "Payout ID is required" });
      return;
    }

    await updateDriverPayoutStatus({
      payoutId,
      status: "rejected",
      treasurerUid: decoded.uid,
      rejectionReason,
    });

    res.status(200).json({ success: true, status: "rejected" });
  } catch (error) {
    console.error("rejectDriverPayout error:", error);
    res.status(500).json({
      success: false,
      message: error.message || "Failed to reject driver payout",
    });
  }
});

exports.cancelDriverPayout = functions.https.onRequest(async (req, res) => {
  setCorsHeaders(res);
  if (handleOptionsRequest(req, res)) return;

  if (req.method !== "POST") {
    res.status(405).json({ success: false, message: "Method not allowed" });
    return;
  }

  try {
    const decoded = await verifyAuthToken(req);
    const payoutId = (req.body.payoutId || "").toString().trim();
    if (!payoutId) {
      res.status(400).json({ success: false, message: "Payout ID is required" });
      return;
    }

    const payoutRef = db.collection("driver_payouts").doc(payoutId);
    const payoutSnapshot = await payoutRef.get();
    if (!payoutSnapshot.exists) {
      res.status(404).json({ success: false, message: "Driver payout request not found" });
      return;
    }

    const payout = payoutSnapshot.data() || {};
    const driverId = (payout.driverId || "").toString().trim();
    if (!(await canAccessDriver(decoded, driverId))) {
      res.status(403).json({ success: false, message: "Driver access required" });
      return;
    }

    await db.runTransaction(async (transaction) => {
      const freshDoc = await transaction.get(payoutRef);
      if (!freshDoc.exists) {
        throw new Error("Driver payout request not found");
      }

      const freshPayout = freshDoc.data() || {};
      if (freshPayout.status !== "requested") {
        throw new Error("Only requested payouts can be cancelled");
      }

      transaction.set(payoutRef, {
        status: "cancelled",
        cancelledBy: "driver",
        cancelledByDriverId: driverId,
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    res.status(200).json({ success: true, status: "cancelled" });
  } catch (error) {
    console.error("cancelDriverPayout error:", error);
    res.status(500).json({
      success: false,
      message: error.message || "Failed to cancel driver payout",
    });
  }
});

async function createDriverPayoutRequest({ driverId, amount }) {
  const payoutRef = db.collection("driver_payouts").doc();
  const earningsRef = db.collection("driver_earnings").doc(driverId);

  let balanceBefore = 0;

  await db.runTransaction(async (transaction) => {
    const earningsDoc = await transaction.get(earningsRef);
    if (!earningsDoc.exists) {
      throw new Error("Driver earnings not found");
    }

    const activePayouts = await transaction.get(
      db.collection("driver_payouts")
        .where("driverId", "==", driverId)
        .where("status", "==", "requested")
        .limit(1)
    );
    if (!activePayouts.empty) {
      throw new Error("A cash payout request is already pending");
    }

    const earnings = earningsDoc.data() || {};
    balanceBefore = Number(earnings.balance || 0);
    if (balanceBefore < amount) {
      throw new Error("Insufficient driver earnings");
    }

    transaction.set(payoutRef, {
      driverId,
      amount,
      method: "cash",
      status: "requested",
      balanceBefore,
      balanceAfter: balanceBefore,
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  return {
    payoutId: payoutRef.id,
    status: "requested",
    balanceBefore,
    balanceAfter: balanceBefore,
  };
}

async function updateDriverPayoutStatus({
  payoutId,
  status,
  treasurerUid,
  rejectionReason,
}) {
  const payoutRef = db.collection("driver_payouts").doc(payoutId);

  await db.runTransaction(async (transaction) => {
    const payoutDoc = await transaction.get(payoutRef);
    if (!payoutDoc.exists) {
      throw new Error("Driver payout request not found");
    }

    const payout = payoutDoc.data() || {};
    if (payout.status !== "requested") {
      throw new Error("Driver payout request is already processed");
    }

    const amount = Number(payout.amount || 0);
    const earningsRef = db.collection("driver_earnings").doc(payout.driverId);
    const notificationRef = db.collection("notifications").doc();
    const updateData = {
      status,
      reviewedBy: treasurerUid,
      reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (status === "paid") {
      const earningsDoc = await transaction.get(earningsRef);
      if (!earningsDoc.exists) {
        throw new Error("Driver earnings not found");
      }

      const earnings = earningsDoc.data() || {};
      const balanceBefore = Number(earnings.balance || 0);
      if (!Number.isFinite(amount) || amount <= 0) {
        throw new Error("Invalid payout amount");
      }
      if (balanceBefore < amount) {
        throw new Error("Insufficient driver earnings");
      }

      const balanceAfter = balanceBefore - amount;
      updateData.paidBy = treasurerUid;
      updateData.paidAt = admin.firestore.FieldValue.serverTimestamp();
      updateData.balanceBefore = balanceBefore;
      updateData.balanceAfter = balanceAfter;
      transaction.update(earningsRef, {
        balance: balanceAfter,
        lifetimeWithdrawn: admin.firestore.FieldValue.increment(amount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      transaction.set(notificationRef, {
        driverId: payout.driverId,
        payoutId,
        type: "driver_payout_paid",
        title: "Cash payout approved",
        message: `Your cash payout of PHP ${amount.toFixed(2)} was approved and deducted from your earnings.`,
        amount,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } else {
      updateData.rejectionReason = rejectionReason || "Rejected by treasurer";

      transaction.set(notificationRef, {
        driverId: payout.driverId,
        payoutId,
        type: "driver_payout_rejected",
        title: "Cash payout rejected",
        message: `Your cash payout request of PHP ${amount.toFixed(2)} was rejected.`,
        amount,
        rejectionReason: updateData.rejectionReason,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    transaction.update(payoutRef, updateData);
  });
}

// ---------------------------------------------------------------------------
// Legacy PayMongo functions were removed. The cooperative flow is now cash and
// AI-scanned GCash receipt based.
// ---------------------------------------------------------------------------
