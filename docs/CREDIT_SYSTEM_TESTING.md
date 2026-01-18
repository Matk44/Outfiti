# Credit System Testing Guide

## Test Scenarios

### Scenario 1: Free User Credit Refill ✅
**Setup:**
1. Create test user with free plan
2. Set `credits: 0` and `lastMonthlyGrant: 30+ days ago`

**Expected Result:**
- `grantMonthlyCredits` should grant 2 credits
- User should have `credits: 2, maxCredits: 2`

**How to Test:**
```javascript
// In Firestore Console
users/{testUserId}
{
  plan: 'free',
  credits: 0,
  maxCredits: 2,
  lastMonthlyGrant: <timestamp 31 days ago>
}

// Then trigger grantMonthlyCredits
// Verify credits = 2
```

---

### Scenario 2: Free User Partial Refill ✅
**Setup:**
1. Free user with 1 credit remaining
2. `lastMonthlyGrant: 30+ days ago`

**Expected Result:**
- `grantMonthlyCredits` should add 1 credit (min(1+2, 2) = 2)
- User should have `credits: 2`

---

### Scenario 3: Pro User NOT Getting Duplicate Credits ✅
**Setup:**
1. User with `plan: 'monthly_pro'`
2. `lastMonthlyGrant: 30+ days ago`

**Expected Result:**
- `grantMonthlyCredits` should **SKIP** this user (not grant credits)
- Only `processSubscriptionRenewals` handles pro users

**How to Verify:**
- Check function logs: should see skip message for pro users
- Credits should NOT increase from grantMonthlyCredits

---

### Scenario 4: Pro User Subscription Renewal ✅
**Setup:**
1. User with active subscription in RevenueCat
2. Subscription document with `expiresDate: <past date>`
3. RevenueCat shows new `expires_date` in future

**Expected Result:**
- `processSubscriptionRenewals` queries RevenueCat
- Finds renewed subscription
- Grants 50 credits (capped at 100)
- Updates `expiresDate` and `lastCreditGrant`

**How to Test:**
```javascript
// In Firestore Console
subscriptions/{userId}
{
  uid: 'test-user-id',
  expiresDate: <yesterday>,
  status: 'active'
}

// Trigger processSubscriptionRenewals
// Verify:
// - Credits increased by 50
// - expiresDate updated to new date from RevenueCat
// - lastCreditGrant updated
```

---

### Scenario 5: Cancelled Subscription Expiration ✅
**Setup:**
1. User with `plan: 'monthly_pro'`
2. Subscription document with `expiresDate: <past date>`
3. RevenueCat shows NO active entitlement

**Expected Result:**
- `processSubscriptionRenewals` queries RevenueCat
- Finds no active Pro entitlement
- Downgrades user to free plan
- Sets `maxCredits: 2` (fixed from 5)
- Marks subscription as `status: 'expired'`

**How to Test:**
```javascript
// Cancel subscription in RevenueCat dashboard first
// Then in Firestore:
subscriptions/{userId}
{
  expiresDate: <yesterday>,
  status: 'active'
}

// Trigger processSubscriptionRenewals
// Verify:
// - user.plan = 'free'
// - user.maxCredits = 2 (not 5!)
// - subscription.status = 'expired'
```

---

### Scenario 6: Restore Purchase Preserves Credit Tracking ✅
**Setup:**
1. User with existing subscription
2. Call `handleRestorePurchase` from app

**Expected Result:**
- Plan and maxCredits synced
- `lastCreditGrant` preserved (not reset to now)
- NO additional credits granted

**How to Test:**
- Call function from app or Firebase Console
- Verify `lastCreditGrant` unchanged
- Verify credits unchanged

---

## Quick Test Commands

### 1. Check Function Logs
```bash
# View logs for grantMonthlyCredits
firebase functions:log --only grantMonthlyCredits

# View logs for processSubscriptionRenewals
firebase functions:log --only processSubscriptionRenewals
```

### 2. Query Test Users
```bash
# Find free users who haven't had credits in 30+ days
# (Should be processed by grantMonthlyCredits)

# Find pro users
# (Should be SKIPPED by grantMonthlyCredits)
```

### 3. Monitor Credit Changes
Watch the `users` collection in [Firestore Console](https://console.firebase.google.com/project/hairaisalon/firestore) for:
- Free users: credits refilled to max 2
- Pro users: credits only change via processSubscriptionRenewals

---

## Expected Behaviors After Fix

### grantMonthlyCredits (runs daily midnight UTC)
✅ Processes ONLY free users
✅ Skips monthly_pro and annual_pro users
✅ Grants up to 2 credits max
✅ Updates lastMonthlyGrant

**Log Example:**
```
Processed: 100, Granted: 45, Errors: 0
(45 = only free users who hadn't been granted in 30+ days)
```

### processSubscriptionRenewals (runs daily midnight UTC)
✅ Queries subscriptions where expiresDate <= now
✅ Checks RevenueCat for each
✅ If renewed: grants 50 credits, updates expiresDate
✅ If expired: downgrades to free (maxCredits: 2), marks expired

**Log Example:**
```
Found 15 subscriptions to check
Processed: 15, Renewed: 8, Expired: 7, Errors: 0
```

---

## Critical Test: No Duplicate Credits

**The Big Fix:** Pro users should NEVER get credits from both functions.

**How to Verify:**
1. Create pro user with `lastMonthlyGrant: 31 days ago`
2. Manually trigger `grantMonthlyCredits`
3. Check logs - should say "skipped pro user"
4. Check user credits - should be UNCHANGED
5. Only `processSubscriptionRenewals` should modify pro user credits

---

## Production Monitoring

After deployment, monitor for 48 hours:

**Day 1 (Today):**
- Functions deployed ✅
- Wait for midnight UTC

**Day 2 (Tomorrow after midnight UTC):**
- Check Cloud Functions logs
- Verify grantMonthlyCredits only processed free users
- Verify processSubscriptionRenewals checked RevenueCat
- Check for any duplicate credit grants (should be ZERO)

**Firestore Console Checks:**
1. Free users: `credits <= 2, maxCredits = 2`
2. Pro users: `credits <= 100, maxCredits = 100`
3. Expired subscriptions: `plan = 'free', maxCredits = 2`

---

## Troubleshooting

### If you see duplicate credits:
- Check function logs for which function granted them
- Verify pro users are being skipped in grantMonthlyCredits
- Check if processSubscriptionRenewals is verifying with RevenueCat

### If expired subscriptions not downgraded:
- Check processSubscriptionRenewals logs
- Verify RevenueCat API key is working
- Check if subscriptions collection has correct expiresDate

### If free users not getting refills:
- Check lastMonthlyGrant timestamp (must be 30+ days ago)
- Verify plan = 'free'
- Check function logs for errors

---

## Manual Testing Checklist

- [ ] Trigger grantMonthlyCredits manually
- [ ] Verify pro users skipped in logs
- [ ] Verify free users with old lastMonthlyGrant got credits
- [ ] Trigger processSubscriptionRenewals manually
- [ ] Verify RevenueCat API called (check logs)
- [ ] Create test free user, wait 30 days (or manipulate timestamp)
- [ ] Create test pro user, verify skipped by grantMonthlyCredits
- [ ] Cancel test subscription, verify downgrade to free with maxCredits: 2
- [ ] Restore purchase, verify lastCreditGrant preserved

---

*Last Updated: 2025-01-06*
