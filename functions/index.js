/**
 * Firebase Cloud Functions owned by the ByaheroX Driver app.
 *
 * High-frequency GPS/crowd writes remain direct Firestore writes. This backend
 * handles driver-side notifications and scheduled stale-location cleanup.
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

const WAITING_LOCATION_ACTIVE_MS = 15 * 60 * 1000;
const WAITING_OFFBOARD_TIMEOUT_MS = 10 * 60 * 1000;
const STALE_LOCATION_MS = 3 * 60 * 1000;
const PAYMONGO_API = "https://api.paymongo.com/v1";

function paymongoConfig() {
  const configured = functions.config().paymongo || {};
  return {
    secretKey: process.env.PAYMONGO_SECRET_KEY || configured.secret_key || "",
  };
}

function paymongoAuthHeader() {
  const { secretKey } = paymongoConfig();
  const encoded = Buffer.from(secretKey + ":").toString("base64");
  return `Basic ${encoded}`;
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

async function postPaymongo(path, body) {
  const response = await fetch(`${PAYMONGO_API}${path}`, {
    method: "POST",
    headers: {
      Authorization: paymongoAuthHeader(),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = payload.errors?.[0]?.detail || payload.message || response.statusText;
    const error = new Error(message);
    error.details = payload;
    throw error;
  }
  return payload;
}

async function canAccessDriverAccount(driverId, decodedToken) {
  if (!decodedToken) {
    return false;
  }

  if (driverId === decodedToken.uid) {
    return true;
  }

  const driverDoc = await db.collection("driver").doc(driverId).get();
  if (!driverDoc.exists) {
    return false;
  }

  const data = driverDoc.data() || {};
  const authEmail = (decodedToken.email || "").toString().trim().toLowerCase();
  const driverEmail = (data.email || "").toString().trim().toLowerCase();

  return data.uid === decodedToken.uid ||
    data.firebaseUid === decodedToken.uid ||
    (authEmail && driverEmail && authEmail === driverEmail);
}

function readCoordinate(data, shortField, legacyField) {
  const value = data[shortField] !== undefined ? data[shortField] : data[legacyField];
  const coordinate = Number(value);
  return Number.isFinite(coordinate) ? coordinate : null;
}

function calculateDistance(lat1, lon1, lat2, lon2) {
  const radiusKm = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) *
      Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return radiusKm * c;
}

function formatDistance(distanceKm) {
  if (!Number.isFinite(distanceKm)) {
    return "nearby";
  }
  if (distanceKm < 1) {
    return `${Math.max(1, Math.round(distanceKm * 1000))}m`;
  }
  return `${distanceKm.toFixed(1)}km`;
}

function readTimestampMillis(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }

  const seconds = value.seconds ?? value._seconds;
  if (Number.isFinite(seconds)) {
    const nanoseconds = value.nanoseconds ?? value._nanoseconds ?? 0;
    return seconds * 1000 + Math.floor(nanoseconds / 1000000);
  }

  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function waitingLocationExpiresAtMillis(data) {
  const expiresAtMillis = readTimestampMillis(data.expiresAt);
  if (expiresAtMillis !== null) {
    return expiresAtMillis;
  }

  const timestampMillis = readTimestampMillis(data.timestamp);
  if (timestampMillis === null) {
    return null;
  }

  return timestampMillis + WAITING_LOCATION_ACTIVE_MS;
}

function isActiveWaitingLocation(data, nowMillis = Date.now()) {
  if (data.isSharing !== true) {
    return false;
  }

  const expiresAtMillis = waitingLocationExpiresAtMillis(data);
  return expiresAtMillis !== null && expiresAtMillis > nowMillis;
}

exports.driverNotifyWaitingCommuters = functions.firestore
  .document("commuter_waiting_location/{commuterId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) {
      return;
    }

    const commuterData = change.after.data();
    const nowMillis = Date.now();
    if (!isActiveWaitingLocation(commuterData, nowMillis)) {
      return;
    }

    const locationsSnapshot = await db.collection("locations").get();
    if (locationsSnapshot.empty) {
      return;
    }

    const notificationPromises = locationsSnapshot.docs.map(async (locationDoc) => {
      const jeepneyId = locationDoc.id;
      const locationData = locationDoc.data();
      const jeepneyLat = readCoordinate(locationData, "lat", "latitude");
      const jeepneyLng = readCoordinate(locationData, "lng", "longitude");

      if (jeepneyLat === null || jeepneyLng === null) {
        return;
      }
      if (locationData.isOnline === false || locationData.isOnTrip === false) {
        return;
      }

      const driverDestination = (locationData.destinationTerminal || "").toString().trim();
      const jeepneyDoc = await db.collection("jeepneys").doc(jeepneyId).get();
      if (!jeepneyDoc.exists) {
        return;
      }

      const jeepneyData = jeepneyDoc.data() || {};
      const driverId = jeepneyData.assignedDriver || jeepneyData.driverId || locationData.driverDocId;
      if (!driverId) {
        return;
      }

      const driverDoc = await db.collection("driver").doc(driverId).get();
      if (!driverDoc.exists) {
        return;
      }

      const driverData = driverDoc.data() || {};
      const fcmToken = driverData.fcmToken;
      if (!fcmToken) {
        return;
      }

      const commutersSnapshot = await db.collection("commuter_waiting_location").get();
      let count = 0;
      let nearestDistanceKm = null;

      commutersSnapshot.docs.forEach((commuterDoc) => {
        const commuterLoc = commuterDoc.data();
        if (!isActiveWaitingLocation(commuterLoc, nowMillis)) {
          return;
        }

        const commuterLat = readCoordinate(commuterLoc, "lat", "latitude");
        const commuterLng = readCoordinate(commuterLoc, "lng", "longitude");
        if (commuterLat === null || commuterLng === null) {
          return;
        }

        const commuterDestination = (commuterLoc.destinationTerminal || "").toString().trim();
        if (driverDestination && commuterDestination && commuterDestination !== driverDestination) {
          return;
        }

        const distance = calculateDistance(jeepneyLat, jeepneyLng, commuterLat, commuterLng);
        if (distance <= 5) {
          count += Number(commuterLoc.waitingCount || 1);
          if (nearestDistanceKm === null || distance < nearestDistanceKm) {
            nearestDistanceKm = distance;
          }
        }
      });

      if (count <= 0) {
        return;
      }

      const distanceText = formatDistance(nearestDistanceKm);
      const passengerLabel = count === 1 ? "passenger" : "passengers";
      const notificationText = `In ${distanceText}, there are ${count} ${passengerLabel} waiting.`;

      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: "Passengers Waiting",
          body: notificationText,
        },
        data: {
          type: "waiting_commuters",
          count: count.toString(),
          distance: distanceText,
          jeepneyId,
        },
      });

      await db.collection("notifications").add({
        driverId,
        title: "Passengers Waiting",
        message: notificationText,
        type: "waiting_commuters",
        commuterId: context.params.commuterId,
        jeepneyId,
        destinationTerminal: driverDestination || null,
        waitingCount: count,
        nearestDistanceKm,
        distanceText,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await Promise.all(notificationPromises);
  });

exports.driverCleanupStaleLocations = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async () => {
    const cutoffMillis = Date.now() - STALE_LOCATION_MS;
    const snapshot = await db.collection("locations")
      .where("isOnline", "==", true)
      .get();

    const batch = db.batch();
    let staleCount = 0;
    snapshot.docs.forEach((doc) => {
      const data = doc.data() || {};
      const timestampMillis = readTimestampMillis(data.timestamp || data.updatedAt);
      if (timestampMillis !== null && timestampMillis < cutoffMillis) {
        staleCount += 1;
        batch.update(doc.ref, {
          isOnline: false,
          isOnTrip: false,
          staleOfflineAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    });

    if (staleCount > 0) {
      await batch.commit();
    }

    console.log(`driverCleanupStaleLocations marked ${staleCount} locations offline`);

    // Auto-offboard waiting commuters past 10 minutes
    const offboardCutoff = Date.now() - WAITING_OFFBOARD_TIMEOUT_MS;
    const waitingSnapshot = await db.collection("commuter_waiting_location")
      .where("status", "==", "waiting")
      .get();

    let offboardCount = 0;
    const offboardBatch = db.batch();
    waitingSnapshot.docs.forEach((doc) => {
      const data = doc.data() || {};
      const timestampMillis = readTimestampMillis(data.timestamp);
      if (timestampMillis !== null && timestampMillis < offboardCutoff) {
        offboardCount += 1;
        offboardBatch.update(doc.ref, {
          status: "offboard",
          isSharing: false,
        });
      }
    });

    if (offboardCount > 0) {
      await offboardBatch.commit();
    }

    console.log(`driverCleanupStaleLocations offboarded ${offboardCount} stale waiting commuters`);
  });

exports.processDriverPayout = functions.https.onRequest(async (req, res) => {
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

    const { driverId, amount, payoutMethod } = req.body;

    if (!driverId) {
      res.status(400).json({ success: false, message: "Driver ID is required" });
      return;
    }

    if (!amount || amount <= 0) {
      res.status(400).json({ success: false, message: "Invalid amount" });
      return;
    }

    if (!payoutMethod || !payoutMethod.accountNumber || !payoutMethod.accountName) {
      res.status(400).json({ success: false, message: "Payout method details required" });
      return;
    }

    if (!(await canAccessDriverAccount(driverId, decoded))) {
      res.status(403).json({ success: false, message: "Driver account mismatch" });
      return;
    }

    const earningsRef = db.collection("driver_earnings").doc(driverId);
    const earningsDoc = await earningsRef.get();

    if (!earningsDoc.exists) {
      res.status(400).json({ success: false, message: "No earnings account found" });
      return;
    }

    const currentBalance = earningsDoc.data().balance || 0;
    if (currentBalance < amount) {
      res.status(400).json({ success: false, message: "Insufficient earnings balance" });
      return;
    }

    const payoutDocRef = db.collection("driver_payouts").doc();
    const payoutPayload = await postPaymongo("/payouts", {
      data: {
        attributes: {
          amount: Math.round(amount * 100),
          currency: "PHP",
          destination: {
            type: payoutMethod.type || "gcash",
            account_number: payoutMethod.accountNumber,
            account_name: payoutMethod.accountName,
          },
          metadata: {
            driverPayoutId: payoutDocRef.id,
            driverId,
            requestedByUid: decoded.uid,
          },
        },
      },
    });

    const payoutIntent = payoutPayload.data;
    const paymongoPayoutId = payoutIntent.id;

    const batch = db.batch();
    batch.set(payoutDocRef, {
      driverId,
      driverName: payoutMethod.accountName,
      amount,
      payoutMethod: payoutMethod.type || "gcash",
      accountNumber: payoutMethod.accountNumber,
      accountName: payoutMethod.accountName,
      paymongoPayoutId,
      status: "processing",
      requestedByUid: decoded.uid,
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    batch.update(earningsRef, {
      balance: admin.firestore.FieldValue.increment(-amount),
      lifetimeWithdrawn: admin.firestore.FieldValue.increment(amount),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    res.status(200).json({
      success: true,
      payoutId: payoutDocRef.id,
      paymongoPayoutId,
      status: "processing",
    });
  } catch (error) {
    console.error("processDriverPayout error:", error.details || error.message);
    res.status(500).json({
      success: false,
      message: "Failed to process payout",
      details: error.details || error.message,
    });
  }
});
