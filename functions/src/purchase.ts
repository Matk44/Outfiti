/**
 * Purchase Handling Cloud Functions for Outfiti
 *
 * SECURITY ARCHITECTURE:
 * - Validates purchases with RevenueCat API before granting credits
 * - Stores subscription data in Firestore for renewal tracking
 * - All credit mutations happen server-side only
 *
 * FLOW:
 * 1. App completes purchase via RevenueCat SDK
 * 2. App calls handlePurchaseSuccess with productId
 * 3. Cloud Function validates with RevenueCat API
 * 4. If valid, stores subscription and grants 50 credits
 *
 * REVENUECAT PRODUCT ID:
 * - outfiti_premium_monthly: Monthly Pro subscription
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import * as admin from 'firebase-admin';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// RevenueCat Secret API Key (stored in Firebase Secret Manager)
const REVENUECAT_API_KEY = defineSecret('REVENUECAT_API_KEY');

// RevenueCat Project ID - get from dashboard URL: app.revenuecat.com/projects/PROJECT_ID/...
// NOTE: Not used with V1 API endpoint (V1 doesn't require project ID)
// const REVENUECAT_PROJECT_ID = 'proj109b9d66';

// ============================================================
// TYPE DEFINITIONS
// ============================================================

type PlanType = 'monthly_pro' | 'annual_pro';

// RevenueCat V2 API response types (not used with V1 endpoint)
// interface V2Subscription {
//   id: string;
//   product_id: string;
//   status: 'active' | 'expired' | 'in_grace_period' | 'in_billing_retry' | 'paused' | 'unknown';
//   starts_at: string;
//   current_period_start: string;
//   current_period_end: string;
//   entitlement?: {
//     lookup_key: string;
//   };
// }
//
// interface V2SubscriptionsResponse {
//   items: V2Subscription[];
//   next_page?: string;
// }

interface RevenueCatSubscriber {
  subscriber?: {
    entitlements?: {
      // IMPORTANT: 'Pro' must match the entitlement ID in RevenueCat dashboard (case-sensitive)
      Pro?: {
        expires_date?: string;
        purchase_date?: string;
        product_identifier?: string;
        original_purchase_date?: string;
      };
    };
    subscriptions?: Record<string, {
      original_purchase_date?: string;
      expires_date?: string;
    }>;
  };
}

interface SubscriptionData {
  uid: string;
  productId: string;
  plan: PlanType;
  purchaseDate: admin.firestore.Timestamp;
  expiresDate: admin.firestore.Timestamp;
  originalTransactionId: string;
  lastCreditGrant: admin.firestore.Timestamp;
  status: 'active' | 'expired' | 'cancelled';
}

// ============================================================
// CONFIGURATION
// ============================================================

const PRODUCT_TO_PLAN: Record<string, PlanType> = {
  'outfiti_premium_monthly': 'monthly_pro',
  // Note: No annual plan for Outfiti - only monthly subscription
};

const PLAN_CONFIG: Record<PlanType, { monthlyCredits: number; maxCredits: number }> = {
  monthly_pro: { monthlyCredits: 50, maxCredits: 100 },
  annual_pro: { monthlyCredits: 50, maxCredits: 100 },
};

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/**
 * Fetch subscriber data from RevenueCat API v2
 *
 * IMPORTANT: Using V2 endpoint because our API key is a V2 Secret Key.
 * V2 Secret Keys are NOT compatible with V1 endpoints.
 *
 * NOTE: The previous 404 errors were caused by alias issues (anonymous ID → Firebase UID).
 * Now that we've fixed the app to use Firebase UID from the start, V2 API should work.
 */
async function getRevenueCatSubscriber(
  appUserId: string,
  apiKey: string
): Promise<RevenueCatSubscriber> {
  // V2 API endpoint - required for V2 Secret API keys
  const url = `https://api.revenuecat.com/v1/subscribers/${appUserId}`;

  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`RevenueCat API error: ${response.status} - ${errorBody}`);
    throw new Error(`RevenueCat API error: ${response.status}`);
  }

  // V1 subscriber endpoint returns the format we need
  const data = await response.json();
  return data as RevenueCatSubscriber;
}

/**
 * Transform V2 API response to match our V1-style interface
 * NOTE: Not used anymore - kept for reference
 */
/* eslint-disable @typescript-eslint/no-unused-vars */
// function transformV2ToV1Format(v2Data: V2SubscriptionsResponse): RevenueCatSubscriber {
//   const subscriptions = v2Data.items || [];
//
//   // Find the active Pro subscription
//   const activeSubscription = subscriptions.find(
//     (sub) => sub.entitlement?.lookup_key === 'Pro' && sub.status === 'active'
//   );
//
//   if (!activeSubscription) {
//     return { subscriber: { entitlements: {} } };
//   }
//
//   return {
//     subscriber: {
//       entitlements: {
//         Pro: {
//           expires_date: activeSubscription.current_period_end,
//           purchase_date: activeSubscription.current_period_start,
//           product_identifier: activeSubscription.product_id,
//           original_purchase_date: activeSubscription.starts_at,
//         },
//       },
//       subscriptions: {
//         [activeSubscription.product_id]: {
//           original_purchase_date: activeSubscription.starts_at,
//           expires_date: activeSubscription.current_period_end,
//         },
//       },
//     },
//   };
// }

/**
 * Extract purchase date from RevenueCat response
 */
function getPurchaseDate(subscriberData: RevenueCatSubscriber, productId: string): Date {
  const entitlement = subscriberData.subscriber?.entitlements?.Pro;
  if (entitlement?.purchase_date) {
    return new Date(entitlement.purchase_date);
  }

  const subscription = subscriberData.subscriber?.subscriptions?.[productId];
  if (subscription?.original_purchase_date) {
    return new Date(subscription.original_purchase_date);
  }

  return new Date();
}

/**
 * Get original transaction ID for subscription tracking
 */
function getOriginalTransactionId(subscriberData: RevenueCatSubscriber, productId: string): string {
  const subscription = subscriberData.subscriber?.subscriptions?.[productId];
  return subscription?.original_purchase_date || productId;
}

// ============================================================
// CLOUD FUNCTIONS
// ============================================================

/**
 * Handle successful purchase from RevenueCat
 *
 * Called by Flutter app after RevenueCat SDK purchase completes.
 * Validates with RevenueCat API and grants credits.
 *
 * INPUT: { productId: string }
 * RETURNS: { success: true, plan: string, creditsGranted: number }
 */
export const handlePurchaseSuccess = onCall(
  {
    secrets: [REVENUECAT_API_KEY],
    memory: '256MiB',
    consumeAppCheckToken: true,
  },
  async (request) => {
    // SECURITY: Require authentication
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'You must be logged in to complete a purchase'
      );
    }

    const uid = request.auth.uid;
    const { productId } = request.data as { productId?: string };

    // Validate product ID
    if (!productId) {
      throw new HttpsError('invalid-argument', 'Product ID is required');
    }

    const plan = PRODUCT_TO_PLAN[productId];
    if (!plan) {
      throw new HttpsError(
        'invalid-argument',
        `Invalid product ID: ${productId}`
      );
    }

    console.log(`Processing purchase for user ${uid}: ${productId}`);

    try {
      // Verify with RevenueCat API that user has active subscription
      const subscriberData = await getRevenueCatSubscriber(
        uid,
        REVENUECAT_API_KEY.value()
      );

      const entitlement = subscriberData.subscriber?.entitlements?.Pro;

      // Check if pro entitlement is active
      if (!entitlement?.expires_date) {
        console.error(`No active subscription found for user ${uid}`);
        throw new HttpsError(
          'failed-precondition',
          'No active subscription found. Please try again.'
        );
      }

      const expiresDate = new Date(entitlement.expires_date);
      if (expiresDate <= new Date()) {
        console.error(`Subscription expired for user ${uid}: ${expiresDate}`);
        throw new HttpsError(
          'failed-precondition',
          'Subscription has expired. Please renew your subscription.'
        );
      }

      // Extract subscription details
      const purchaseDate = getPurchaseDate(subscriberData, productId);
      const originalTransactionId = getOriginalTransactionId(subscriberData, productId);
      const config = PLAN_CONFIG[plan];
      const now = admin.firestore.Timestamp.now();

      // Store subscription and grant credits in a transaction
      await db.runTransaction(async (transaction) => {
        const userRef = db.collection('users').doc(uid);
        const subscriptionRef = db.collection('subscriptions').doc(uid);

        const userDoc = await transaction.get(userRef);
        const userData = userDoc.exists ? userDoc.data() : {};
        const currentCredits = userData?.credits ?? 0;

        // Grant 50 credits immediately (capped at maxCredits)
        const newCredits = Math.min(currentCredits + 50, config.maxCredits);

        // Update user document with plan and credits
        transaction.set(
          userRef,
          {
            plan: plan,
            credits: newCredits,
            maxCredits: config.maxCredits,
            lastMonthlyGrant: now,
          },
          { merge: true }
        );

        // Store subscription data for renewal tracking
        const subscriptionData: SubscriptionData = {
          uid: uid,
          productId: productId,
          plan: plan,
          purchaseDate: admin.firestore.Timestamp.fromDate(purchaseDate),
          expiresDate: admin.firestore.Timestamp.fromDate(expiresDate),
          originalTransactionId: originalTransactionId,
          lastCreditGrant: now,
          status: 'active',
        };

        transaction.set(subscriptionRef, subscriptionData);
      });

      console.log(
        `Purchase validated for ${uid}: ${plan}, granted 50 credits, expires: ${expiresDate}`
      );

      return {
        success: true,
        plan: plan,
        creditsGranted: 50,
        expiresDate: expiresDate.toISOString(),
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error(`Error processing purchase for user ${uid}:`, error);
      throw new HttpsError('internal', 'Failed to process purchase. Please try again.');
    }
  }
);

/**
 * Handle restore purchases from RevenueCat
 *
 * Called by Flutter app when user clicks "Restore Purchases".
 * Validates subscription with RevenueCat API and syncs status,
 * but DOES NOT grant any additional credits (prevents exploit).
 *
 * INPUT: { productId: string }
 * RETURNS: { success: true, plan: string }
 */
export const handleRestorePurchase = onCall(
  {
    secrets: [REVENUECAT_API_KEY],
    memory: '256MiB',
    consumeAppCheckToken: true,
  },
  async (request) => {
    // SECURITY: Require authentication
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'You must be logged in to restore purchases'
      );
    }

    const uid = request.auth.uid;
    const { productId } = request.data as { productId?: string };

    // Validate product ID
    if (!productId) {
      throw new HttpsError('invalid-argument', 'Product ID is required');
    }

    const plan = PRODUCT_TO_PLAN[productId];
    if (!plan) {
      throw new HttpsError(
        'invalid-argument',
        `Invalid product ID: ${productId}`
      );
    }

    console.log(`Processing restore for user ${uid}: ${productId}`);

    try {
      // Verify with RevenueCat API that user has active subscription
      const subscriberData = await getRevenueCatSubscriber(
        uid,
        REVENUECAT_API_KEY.value()
      );

      const entitlement = subscriberData.subscriber?.entitlements?.Pro;

      // Check if pro entitlement is active
      if (!entitlement?.expires_date) {
        console.error(`No active subscription found for user ${uid}`);
        throw new HttpsError(
          'failed-precondition',
          'No active subscription found to restore.'
        );
      }

      const expiresDate = new Date(entitlement.expires_date);
      if (expiresDate <= new Date()) {
        console.error(`Subscription expired for user ${uid}: ${expiresDate}`);
        throw new HttpsError(
          'failed-precondition',
          'Subscription has expired.'
        );
      }

      // Extract subscription details
      const purchaseDate = getPurchaseDate(subscriberData, productId);
      const originalTransactionId = getOriginalTransactionId(subscriberData, productId);
      const config = PLAN_CONFIG[plan];
      const now = admin.firestore.Timestamp.now();

      // Update subscription status WITHOUT granting additional credits
      await db.runTransaction(async (transaction) => {
        const userRef = db.collection('users').doc(uid);
        const subscriptionRef = db.collection('subscriptions').doc(uid);

        const userDoc = await transaction.get(userRef);
        const userData = userDoc.exists ? userDoc.data() : {};
        const currentCredits = userData?.credits ?? 0;

        // Get existing subscription data to preserve lastCreditGrant
        const existingSubDoc = await transaction.get(subscriptionRef);
        const existingData = existingSubDoc.exists ? existingSubDoc.data() : null;

        // CRITICAL: Do NOT grant additional credits on restore
        // Only sync plan and max credits settings
        transaction.set(
          userRef,
          {
            plan: plan,
            credits: currentCredits, // Keep existing credits, don't add
            maxCredits: config.maxCredits,
            // Note: Don't update lastMonthlyGrant on restore
          },
          { merge: true }
        );

        // Store/update subscription data for renewal tracking
        const subscriptionData: SubscriptionData = {
          uid: uid,
          productId: productId,
          plan: plan,
          purchaseDate: admin.firestore.Timestamp.fromDate(purchaseDate),
          expiresDate: admin.firestore.Timestamp.fromDate(expiresDate),
          originalTransactionId: originalTransactionId,
          lastCreditGrant: existingData?.lastCreditGrant || now, // Preserve if exists
          status: 'active',
        };

        transaction.set(subscriptionRef, subscriptionData);
      });

      console.log(
        `Restore validated for ${uid}: ${plan}, credits unchanged, expires: ${expiresDate}`
      );

      return {
        success: true,
        plan: plan,
        expiresDate: expiresDate.toISOString(),
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error(`Error restoring purchase for user ${uid}:`, error);
      throw new HttpsError('internal', 'Failed to restore purchase. Please try again.');
    }
  }
);
