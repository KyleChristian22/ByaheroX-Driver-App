# ByaheroX Commuter Cloud Functions

This codebase is owned by the Commuter app only.

## Functions

- `commuterValidatePasswordReset` - HTTP; validates that a password reset request belongs to an active commuter account and not a driver/admin account.

Commuter login and registration remain direct Firebase Auth client flows.
Admin-owned staff creation and SMTP credential email are in `../../admin/functions`.

## Deploy

```bash
cd commuter
npm --prefix functions install
firebase deploy --only functions --project byaheroxperience
```
