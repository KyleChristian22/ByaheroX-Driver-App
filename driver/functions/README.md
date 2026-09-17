# ByaheroX Driver Cloud Functions

This codebase is owned by the Driver app only.

## Functions

- `driverNotifyWaitingCommuters` - Firestore trigger; sends FCM notifications to assigned drivers when commuters share active pickup locations.
- `driverCleanupStaleLocations` - scheduled; marks online driver locations offline when GPS updates become stale.

High-frequency GPS and crowd status updates remain direct Firestore writes guarded by security rules.

## Deploy

```bash
cd driver
npm --prefix functions install
firebase deploy --only functions --project byaheroxperience
```
