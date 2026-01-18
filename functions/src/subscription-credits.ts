/**
 * Subscription Renewal Processing for HairAI
 *
 * FLOW:
 * 1. Scheduled function runs daily at midnight UTC
 * 2. Queries subscriptions where expiresDate <= now
 * 3. For each, checks RevenueCat API for current status
 * 4. If renewed (new expiresDate > now): grants 50 credits
 * 5. If expired (no active entitlement): downgrades to free plan
 *
 * SECURITY:
 * - Uses Admin SDK for Firestore writes (bypasses security rules)
 * - Validates subscription status with RevenueCat API
 */

import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';
import * as admin from 'firebase-admin';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// RevenueCat Secret API Key
const REVENUECAT_API_KEY = defineSecret('REVENUECAT_API_KEY');

// RevenueCat Project ID - must match the one in purchase.ts
// NOTE: Not used with V1 API endpoint (V1 doesn't require project ID)
// const REVENUECAT_PROJECT_ID = 'proj109b9d66';

// ============================================================
// TYPE DEFINITIONS
// ============================================================

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
      };
    };
  };
}

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/**
 * Fetch subscriber data from RevenueCat API
 *
 * IMPORTANT: Using V1 endpoint because:
 * - Better alias resolution (supports both original and alias IDs)
 * - More stable for newly created customers (no indexing delay)
 * - Works with both V1 (Public) and V2 (Secret) API keys
 * - The V2 endpoints have timing/indexing issues causing 404s
 */
async function getRevenueCatSubscriber(
  appUserId: string,
  apiKey: string
): Promise<RevenueCatSubscriber> {
  // V1 API endpoint - simpler and more reliable
  const url = `https://api.revenuecat.com/v1/subscribers/${appUserId}`;

  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`RevenueCat V1 API error: ${response.status} - ${errorBody}`);
    throw new Error(`RevenueCat API error: ${response.status}`);
  }

  // V1 API returns data in the expected format already
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
//         },
//       },
//     },
//   };
// }

// ============================================================
// SCHEDULED FUNCTION
// ============================================================

/**
 * Process subscription renewals daily
 *
 * Runs at midnight UTC every day.
 * Checks expired subscriptions and grants credits if renewed.
 */
export const processSubscriptionRenewals = onSchedule(
  {
    schedule: '0 0 * * *', // Daily at midnight UTC
    timeZone: 'UTC',
    retryCount: 3,
    memory: '512MiB',
    secrets: [REVENUECAT_API_KEY],
  },
  async () => {
    console.log('Starting subscription renewal processing...');

    const now = admin.firestore.Timestamp.now();
    let processedCount = 0;
    let renewedCount = 0;
    let expiredCount = 0;
    let errorCount = 0;

    try {
      // Get active subscriptions where expiresDate has passed
      const expiredSubs = await db
        .collection('subscriptions')
        .where('status', '==', 'active')
        .where('expiresDate', '<=', now)
        .get();

      console.log(`Found ${expiredSubs.size} subscriptions to check`);

      for (const doc of expiredSubs.docs) {
        processedCount++;
        const sub = doc.data();
        const uid = sub.uid as string;

        try {
          // Check RevenueCat for current subscription status
          const subscriberData = await getRevenueCatSubscriber(
            uid,
            REVENUECAT_API_KEY.value()
          );

          const entitlement = subscriberData.subscriber?.entitlements?.Pro;

          if (entitlement?.expires_date) {
            const newExpiresDate = new Date(entitlement.expires_date);

            if (newExpiresDate > new Date()) {
              // Subscription RENEWED - grant credits
              await db.runTransaction(async (transaction) => {
                // Update subscription record with new expiration
                transaction.update(doc.ref, {
                  expiresDate: admin.firestore.Timestamp.fromDate(newExpiresDate),
                  lastCreditGrant: now,
                });

                // Grant 50 credits (capped at 100)
                const userRef = db.collection('users').doc(uid);
                const userDoc = await transaction.get(userRef);
                const userData = userDoc.exists ? userDoc.data() : {};
                const currentCredits = (userData?.credits as number) ?? 0;
                const maxCredits = (userData?.maxCredits as number) ?? 100;
                const newCredits = Math.min(currentCredits + 50, maxCredits);

                transaction.update(userRef, {
                  credits: newCredits,
                  lastMonthlyGrant: now,
                });
              });

              renewedCount++;
              console.log(
                `Renewal processed for ${uid}: +50 credits, expires: ${newExpiresDate}`
              );
            } else {
              // Entitlement exists but expired - subscription ended
              await handleExpiredSubscription(doc, uid);
              expiredCount++;
            }
          } else {
            // No active entitlement - subscription expired/cancelled
            await handleExpiredSubscription(doc, uid);
            expiredCount++;
          }
        } catch (error) {
          console.error(`Error processing user ${uid}:`, error);
          errorCount++;
        }
      }

      console.log(
        `Subscription renewal processing complete. ` +
          `Processed: ${processedCount}, Renewed: ${renewedCount}, ` +
          `Expired: ${expiredCount}, Errors: ${errorCount}`
      );
    } catch (error) {
      console.error('Failed to run subscription renewal processing:', error);
      throw error; // Trigger retry
    }
  }
);

/**
 * Handle expired subscription - downgrade user to free plan
 */
async function handleExpiredSubscription(
  subscriptionDoc: admin.firestore.QueryDocumentSnapshot,
  uid: string
): Promise<void> {
  // Mark subscription as expired
  await subscriptionDoc.ref.update({
    status: 'expired',
  });

  // Downgrade user to free plan
  await db.collection('users').doc(uid).update({
    plan: 'free',
    maxCredits: 2, // Match PLAN_CONFIG.free
    // Note: We don't reduce current credits, they'll be capped on next use
  });

  console.log(`Subscription expired for ${uid}, downgraded to free plan`);
}
