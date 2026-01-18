# Outfiti Credit System Documentation

## Overview

The Outfiti credit system is a **secure, server-enforced** system that controls access to AI-powered outfit try-on features. All credit mutations happen exclusively through Firebase Cloud Functions, making it tamper-proof against malicious clients.

### Key Principles
- **Server-Side Only**: Credits can ONLY be modified by Cloud Functions (Admin SDK)
- **Firestore Rules Block Client Writes**: Security rules prevent any client-side credit manipulation
- **Atomic Transactions**: All credit operations use Firestore transactions to prevent race conditions
- **Idempotent Operations**: Safe to retry failed operations without side effects
- **Free Onboarding Generation**: First generation during onboarding is FREE (doesn't consume credits)

---

## Business Logic

### Plan Configuration

| Plan | Monthly Credits | Max Balance | Notes |
|------|-----------------|-------------|-------|
| `free` | 2 | 2 | Default for new users (does NOT accumulate) |
| `monthly_pro` | 50 | 100 | Monthly subscription ($9.99/month) |

> **Note**: Credit amounts can be adjusted in `functions/src/credits.ts` in the `PLAN_CONFIG` constant. See [Adjusting Credit Amounts](#adjusting-credit-amounts) section.

### Credit Rules
- Credits are granted monthly (every 30 days from `lastMonthlyGrant`)
- **Free tier credits do NOT roll over** - max 2 credits at any time
- **Pro tier credits can accumulate** up to max balance (100)
- Each AI generation costs **1 credit**
- New users start with 2 free credits
- **First onboarding generation is FREE** (users keep their 2 credits after onboarding)

### Credit Top-Ups (One-Time Purchases)
- **All users** (including free tier) can purchase one-time credit packs
- **15 credits for $4.99** (product ID: `stylecredits_15pack`)
- **5 credits for $2.99** (product ID: `stylecredits_5pack`)
- Purchased credits **NEVER expire** - they persist indefinitely
- **No credit cap for purchases** - purchased credits are not limited by plan's `maxCredits`
- Validated against RevenueCat API to prevent fraud
- Tracked in `processedTransactions` collection to prevent replay attacks

### Subscription Cancellation & Credit Preservation
When a Pro user cancels their subscription:
1. **During billing period**: User keeps all Pro benefits and accumulated credits
2. **At expiration**: User downgrades to Free plan (`maxCredits: 2`)
3. **Purchased credits are preserved**: If user has more than 2 credits (including purchased credits), they keep ALL of them
4. **Monthly grants respect purchased credits**: The system will NOT reduce credits to the free tier limit if they're above it
5. **Credits deplete naturally**: User consumes credits normally until they drop below 2
6. **Monthly grants resume**: Once credits drop below 2, the 30-day monthly grant cycle gives them back up to 2 credits

**Example**:
- Pro user with 75 credits (55 from subscription + 20 purchased) cancels
- At expiration: `plan: 'free'`, `maxCredits: 2`, `credits: 75` (preserved!)
- After 30 days: Still 75 credits (no reduction from monthly grant job)
- User generates 73 outfits → down to 2 credits
- After 30 more days: Granted 0 credits (already at max for free tier)
- User generates 1 outfit → down to 1 credit
- After 30 more days: Granted 1 credit → back to 2 credits

---

## RevenueCat Product Configuration

### Products
| Display Name | Product ID | Package Identifier | Type | Price |
|--------------|------------|-------------------|------|-------|
| Monthly Plan | `outfiti_premium_monthly` | `$rc_monthly` | Subscription | $9.99/month |
| Style Credits - 15 Pack | `stylecredits_15pack` | `$rc_stylecredits` | Consumable | $4.99 |
| One-Time 5 Pack Style Credits | `stylecredits_5pack` | `$rc_stylecredits_5pack` | Consumable | $2.99 |

### Entitlements
| Entitlement ID | Display Name | Associated Products |
|----------------|--------------|---------------------|
| `Pro` | Pro | `outfiti_premium_monthly`, `stylecredits_15pack`, `stylecredits_5pack` |

### Offering
| Offering ID | Display Name |
|-------------|--------------|
| `default` | Outfiti Paid Choices |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        FLUTTER APP                               │
├─────────────────────────────────────────────────────────────────┤
│  CreditService                                                   │
│  ├── getCredits() ──────────► Firestore (READ ONLY)             │
│  ├── creditsStream ─────────► Firestore (READ ONLY)             │
│  ├── consumeCredit(1) ──────► Cloud Function                    │
│  ├── initializeCredits() ───► Cloud Function                    │
│  └── setUserPlan() ─────────► Cloud Function                    │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CLOUD FUNCTIONS (v2)                          │
├─────────────────────────────────────────────────────────────────┤
│  initializeUserCredits ─► Creates user credits (idempotent)     │
│  consumeCredit ─────────► Deducts credits atomically            │
│  setUserPlan ───────────► Updates plan after purchase validation│
│  getUserCredits ────────► Returns fresh credit data             │
│  grantMonthlyCredits ───► Scheduled daily, grants monthly credits│
│  handlePurchaseSuccess ─► Validates subscription, grants credits │
│  handleRestorePurchase ─► Restores subscription (no extra credits)│
│  handleCreditTopUp ─────► 15-pack one-time purchase             │
│  handleCreditTopUp5Pack ► 5-pack one-time purchase              │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                        FIRESTORE                                 │
├─────────────────────────────────────────────────────────────────┤
│  users/{uid}                                                     │
│  ├── credits: number          (PROTECTED - server only)         │
│  ├── maxCredits: number       (PROTECTED - server only)         │
│  ├── plan: string             (PROTECTED - server only)         │
│  ├── lastMonthlyGrant: timestamp (PROTECTED - server only)      │
│  ├── createdAt: timestamp     (PROTECTED - server only)         │
│  └── [profile fields...]      (client can update)               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Firestore Data Model

### User Document (`users/{uid}`)

```typescript
interface UserCredits {
  // Credit system fields (PROTECTED - server only)
  plan: 'free' | 'monthly_pro';
  credits: number;           // Current credit balance
  maxCredits: number;        // Maximum credit cap for current plan
  lastMonthlyGrant: Timestamp; // When credits were last granted
  createdAt: Timestamp;      // User creation timestamp
  usedFreeOnboardingGeneration: boolean; // True if free onboarding generation was used

  // Profile fields (client can update)
  uid: string;
  email: string;
  displayName: string;
  profileImageUrl: string;
  os: string;
  lastLoginTime: Timestamp;
}
```

### Subscription Document (`subscriptions/{uid}`)

Created during initial purchase and updated on renewals/expirations. One subscription document per user.

```typescript
interface SubscriptionData {
  uid: string;                    // Firebase user ID
  productId: string;              // RevenueCat product ID
  plan: 'monthly_pro';
  purchaseDate: Timestamp;        // Original purchase date
  expiresDate: Timestamp;         // Current subscription expiration
  originalTransactionId: string;  // For tracking renewals
  lastCreditGrant: Timestamp;     // When credits were last granted
  status: 'active' | 'expired' | 'cancelled';
}
```

**Lifecycle**:
- Created by `handlePurchaseSuccess` on initial purchase (grants 50 credits)
- Updated by `handleRestorePurchase` when restoring (preserves credit grant tracking)
- Updated by `processSubscriptionRenewals` on renewal (grants 50 credits) or expiration (downgrades to free)
- Used by `processSubscriptionRenewals` to check RevenueCat for subscription status changes

---

## Cloud Functions API Reference

### 1. `initializeUserCredits`
**Type**: Callable HTTPS Function
**When to Call**: After user signup/login
**Idempotent**: Yes (safe to call multiple times)

```dart
// Flutter usage
await creditService.initializeCredits();
```

**Response**:
```json
{
  "success": true,
  "alreadyInitialized": false,
  "credits": 2,
  "maxCredits": 2,
  "plan": "free"
}
```

---

### 2. `consumeCredit`
**Type**: Callable HTTPS Function
**When to Call**: BEFORE any AI generation
**Atomic**: Yes (uses Firestore transaction)

```dart
// Flutter usage
try {
  final remaining = await creditService.consumeCredit(1);
} on InsufficientCreditsException catch (e) {
  // Show upgrade dialog
}
```

**Input**:
```json
{
  "amount": 1
}
```

**Response (Success)**:
```json
{
  "success": true,
  "remainingCredits": 4
}
```

**Response (Insufficient Credits)**:
```json
{
  "code": "resource-exhausted",
  "message": "Insufficient credits. You have 0 credits but need 1."
}
```

---

### 3. `handlePurchaseSuccess`
**Type**: Callable HTTPS Function
**When to Call**: AFTER RevenueCat SDK purchase completes
**Validates**: Purchase with RevenueCat API before granting credits

```dart
// Flutter usage - call AFTER RevenueCat purchase completes
final functions = FirebaseFunctions.instance;
await functions.httpsCallable('handlePurchaseSuccess').call({
  'productId': 'outfiti_premium_monthly',
});
```

**Input**:
```json
{
  "productId": "outfiti_premium_monthly"
}
```

**Response**:
```json
{
  "success": true,
  "plan": "monthly_pro",
  "creditsGranted": 50,
  "expiresDate": "2026-02-15T00:00:00Z"
}
```

---

### 4. `handleCreditTopUp`
**Type**: Callable HTTPS Function
**When to Call**: AFTER user purchases 15-pack credits via RevenueCat
**Available to**: All users (free and pro)
**Amount**: 15 credits for $4.99

```dart
// Flutter usage - call AFTER RevenueCat purchase completes
await functions.httpsCallable('handleCreditTopUp').call({
  'productId': 'stylecredits_15pack',
  'transactionId': transactionId,
});
```

**Logic**:
1. Validates purchase with RevenueCat API
2. Checks for duplicate transactions in `processedTransactions` collection
3. Adds 15 credits (NOT capped - free users can accumulate beyond maxCredits)
4. Records transaction to prevent replay attacks

**Response (Success)**:
```json
{
  "success": true,
  "creditsAdded": 15,
  "newBalance": 17
}
```

---

### 5. `handleCreditTopUp5Pack`
**Type**: Callable HTTPS Function
**When to Call**: AFTER user purchases 5-pack credits via RevenueCat
**Available to**: All users (free and pro)
**Amount**: 5 credits for $2.99

```dart
// Flutter usage - call AFTER RevenueCat purchase completes
await functions.httpsCallable('handleCreditTopUp5Pack').call({
  'productId': 'stylecredits_5pack',
  'transactionId': transactionId,
});
```

**Response (Success)**:
```json
{
  "success": true,
  "creditsAdded": 5,
  "newBalance": 7
}
```

**Important**: Purchased credits **never expire** and are **never reduced** by the monthly grant job. Free tier users can have more than 2 credits if they purchased them.

---

### 6. `grantMonthlyCredits`
**Type**: Scheduled Function
**Schedule**: Daily at midnight UTC (`0 0 * * *`)
**Automatic**: No manual invocation needed

**Logic**:
1. For each user, check if 30 days have passed since `lastMonthlyGrant`
2. **If user has fewer credits than their `maxCredits`**: Add monthly credits (capped at `maxCredits`)
3. **If user has more credits than `maxCredits`**: Preserve their balance (protects purchased credits), only update timestamp
4. Update `lastMonthlyGrant` timestamp

**Important**: This function **never reduces** credit balances. If a free tier user has purchased credits that exceed their `maxCredits` of 2, those credits are preserved indefinitely.

---

### 7. `generateOnboardingOutfit`
**Type**: Callable HTTPS Function
**When to Call**: During onboarding (first outfit generation)
**Idempotent**: Yes (can only be used once per user)
**Credit Cost**: FREE (0 credits)

This function provides a **completely free** first generation during onboarding.
After using this, users still have their full 2 free credits.

```dart
// Flutter usage - called automatically in OnboardingScreen4
final result = await FirebaseOnboardingOutfitService().generateFromDescription(
  selfieImage: userImage,
  userDescription: 'casual streetwear',
  targetColor: 'blue',
);
```

**Response (Success)**:
```json
{
  "imageBase64": "...",
  "freeGeneration": true
}
```

**Response (Already Used)**:
```json
{
  "code": "failed-precondition",
  "message": "Free onboarding generation already used. Please use regular generation."
}
```

**Security**:
- Tracked via `usedFreeOnboardingGeneration` flag in user document
- Can only be used once per user (enforced atomically via Firestore transaction)
- If already used, throws error and client should fall back to regular generation

---

## Flutter Service API Reference

### CreditService (`lib/services/credit_service.dart`)

```dart
final creditService = CreditService();

// ===== READ OPERATIONS (Direct Firestore) =====

// Get current credits (async)
final credits = await creditService.getCredits();
print('Credits: ${credits.credits}/${credits.maxCredits}');
print('Plan: ${credits.plan}');

// Stream for real-time UI updates
StreamBuilder<UserCredits>(
  stream: creditService.creditsStream,
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      return Text('${snapshot.data!.credits} credits');
    }
    return CircularProgressIndicator();
  },
)

// ===== WRITE OPERATIONS (Via Cloud Functions) =====

// Initialize credits (call after login)
await creditService.initializeCredits();

// Consume credit before AI generation
try {
  await creditService.consumeCredit(1);
  // Proceed with AI generation
} on InsufficientCreditsException catch (e) {
  showUpgradeDialog(e.currentCredits);
}

// Update plan after purchase (PAYWALL INTEGRATION POINT)
await creditService.setUserPlan(UserPlan.monthlyPro);

// Check if user can afford operation
if (await creditService.canAfford(1)) {
  // Show generate button enabled
}
```

### UserCredits Model

```dart
class UserCredits {
  final int credits;
  final int maxCredits;
  final UserPlan plan;

  bool hasCredits(int amount) => credits >= amount;
  String get planDisplayName; // "Free", "Pro (Monthly)"
}

enum UserPlan {
  free,
  monthlyPro;

  String toApiString(); // "free", "monthly_pro"
}
```

---

## Paywall Integration (Flutter)

The app uses three paywall screens:
1. **PaywallModal** (`lib/widgets/paywall_modal.dart`) - In-app paywall
2. **OnboardingScreen8** (`lib/screens/onboarding/onboarding_screen_8.dart`) - Onboarding paywall
3. **CreditTopUpModal** (`lib/widgets/credit_topup_modal.dart`) - Credit top-up only

### Purchase Flow

```dart
// Monthly subscription purchase
final package = _offerings!.current!.monthly;
await _revenueCatService.purchasePackage(package);
await Future.delayed(const Duration(seconds: 3)); // Wait for sync
await functions.httpsCallable('handlePurchaseSuccess').call({
  'productId': package.storeProduct.identifier, // 'outfiti_premium_monthly'
});

// 15-pack one-time purchase
final package = _offerings!.current!.availablePackages
    .where((p) => p.identifier == '\$rc_stylecredits')
    .firstOrNull;
final customerInfo = await _revenueCatService.purchasePackage(package);
final transaction = customerInfo.nonSubscriptionTransactions
    .where((t) => t.productIdentifier == package.storeProduct.identifier)
    .reduce((a, b) => ...); // Get most recent
await functions.httpsCallable('handleCreditTopUp').call({
  'productId': 'stylecredits_15pack',
  'transactionId': transaction.transactionIdentifier,
});

// 5-pack one-time purchase
final package = _offerings!.current!.availablePackages
    .where((p) => p.identifier == '\$rc_stylecredits_5pack')
    .firstOrNull;
// ... same pattern as 15-pack ...
await functions.httpsCallable('handleCreditTopUp5Pack').call({
  'productId': 'stylecredits_5pack',
  'transactionId': transaction.transactionIdentifier,
});
```

---

## Adjusting Credit Amounts

To change credit allocations, edit `functions/src/credits.ts`:

```typescript
// Line ~65 in credits.ts
const PLAN_CONFIG: Record<PlanType, PlanConfig> = {
  free: {
    monthlyCredits: 2,    // Free tier (does NOT accumulate)
    maxCredits: 2,        // Free credits cap
  },
  monthly_pro: {
    monthlyCredits: 50,   // Monthly pro credits per month
    maxCredits: 100,      // Monthly pro max balance
  },
};
```

After changing, redeploy:

```bash
cd functions
npm run build
firebase deploy --only functions
```

> **Note**: Changes only affect future credit grants. Existing users keep their current balance.

---

## Security Implementation

### Firestore Rules (`firestore.rules`)

Protected fields that ONLY Cloud Functions can modify:
- `credits`
- `maxCredits`
- `plan`
- `lastMonthlyGrant`
- `createdAt`

```javascript
// Excerpt from firestore.rules
function isValidProfileUpdate() {
  let protectedFields = ['credits', 'maxCredits', 'plan',
                         'lastMonthlyGrant', 'createdAt', 'uid', 'email'].toSet();
  let noProtectedFieldsModified = !updatedKeys.hasAny(protectedFields);
  return noProtectedFieldsModified && onlyAllowedFields;
}
```

### Why This Is Secure
1. **Client cannot modify credits**: Firestore rules block any write to credit fields
2. **Cloud Functions use Admin SDK**: Bypasses security rules
3. **Atomic transactions**: Prevents race conditions during concurrent requests
4. **Idempotent operations**: `initializeUserCredits` won't reset existing credits

---

## UI Components

### Credits Badge (App Bar)

Location: `lib/navigation/home_navbar.dart`

Shows real-time credit balance with coin emoji below profile picture.

### Insufficient Credits Dialog

Location: Each screen (`outfit_try_on_screen.dart`, `ai_try_on_screen.dart`, `describe_screen.dart`)

Shows when user tries to generate without enough credits:
- Current credit count
- "Upgrade" button (opens paywall)
- "Later" button to dismiss

---

## File Reference

| File | Purpose |
|------|---------|
| `functions/src/credits.ts` | All Cloud Functions for credit system |
| `functions/src/purchase.ts` | Purchase and restore subscription handling |
| `functions/src/index.ts` | Exports credit functions + free onboarding generation |
| `firestore.rules` | Security rules blocking client credit writes |
| `lib/services/credit_service.dart` | Flutter service for credit operations |
| `lib/services/outfit_service.dart` | AI outfit generation services |
| `lib/providers/auth_provider.dart` | Initializes credits on login |
| `lib/navigation/home_navbar.dart` | Credits badge UI |
| `lib/screens/*_screen.dart` | Insufficient credits dialog handling |
| `lib/screens/onboarding/onboarding_screen_4.dart` | Uses FREE onboarding generation |
| `lib/screens/onboarding/onboarding_screen_8.dart` | Paywall with subscription + one-time purchase options |
| `lib/widgets/paywall_modal.dart` | In-app paywall with subscription + one-time purchase options |
| `lib/widgets/credit_topup_modal.dart` | Dedicated modal for credit top-up purchases |

---

## Testing Checklist

- [ ] New user gets 2 free credits on signup
- [ ] Credits display correctly in app bar
- [ ] Onboarding generation is FREE (doesn't consume credits)
- [ ] After onboarding, user still has 2 credits
- [ ] Regular AI generation consumes 1 credit
- [ ] Insufficient credits shows dialog
- [ ] Upgrade button navigates to paywall
- [ ] Monthly subscription purchase grants 50 credits
- [ ] 15-pack purchase grants 15 credits
- [ ] 5-pack purchase grants 5 credits
- [ ] Free tier credits don't exceed 2 (from monthly grants)
- [ ] Pro tier credits can accumulate up to 100
- [ ] Cannot manipulate credits via Firestore directly (test with Firebase console)
- [ ] `usedFreeOnboardingGeneration` flag prevents second free generation
- [ ] Purchased credits persist after subscription cancellation
- [ ] Free user with purchased credits keeps all credits (not capped to 2)
- [ ] Monthly grant doesn't reduce credits for users with purchased credits

---

## Troubleshooting

### Credits not showing after signup
- Check if `initializeUserCredits` is being called in `auth_provider.dart`
- Check Cloud Functions logs for errors

### Credits not updating in UI
- Verify `creditsStream` is connected properly
- Check Firestore security rules allow reads

### "resource-exhausted" errors
- User has 0 credits
- Direct them to upgrade

### Purchase validation fails
- Check RevenueCat API key is set in Firebase Secret Manager
- Verify product IDs match between RevenueCat and Cloud Functions
- Check Cloud Functions logs for detailed error messages

---

*Last Updated: January 2026*
*Version: 4.0*

### Changelog
- **v4.0**: Updated for Outfiti app. New product IDs: `outfiti_premium_monthly`, `stylecredits_15pack`, `stylecredits_5pack`. Removed annual plan.
- **v3.0**: One-time credit purchase now available to ALL users (15 credits for $4.99). Purchased credits no longer capped.
- **v2.0**: Reduced free tier to 2 credits (from 5). Added free onboarding generation.
- **v1.0**: Initial credit system with 5 free credits.
