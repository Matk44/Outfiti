/**
 * Credit System Cloud Functions for Outfiti
 *
 * SECURITY ARCHITECTURE:
 * - All credit mutations happen ONLY in these Cloud Functions
 * - Firestore security rules BLOCK any client-side credit modification
 * - Client can only READ credits for UI display
 * - Client must call consumeCredit BEFORE any AI generation
 *
 * BUSINESS LOGIC:
 * Plan         | Monthly Credits | Max Balance
 * -------------|-----------------|-------------
 * free         | 2               | 2 (does NOT accumulate)
 * monthly_pro  | 50              | 100
 *
 * - Free tier credits do NOT roll over (max 2 at any time)
 * - Pro tier credits can accumulate up to max balance
 * - Credits are granted on billing cycle (not calendar month)
 * - First onboarding generation is FREE (doesn't consume credits)
 *
 * REVENUECAT PRODUCT IDs:
 * - outfiti_premium_monthly: Monthly Pro subscription ($9.99/month, 50 credits)
 * - stylecredits_15pack: 15 Style Credits one-time purchase ($4.99)
 * - stylecredits_5pack: 5 Style Credits one-time purchase ($2.99)
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';
import * as admin from 'firebase-admin';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// RevenueCat Secret API Key (for top-up validation)
const REVENUECAT_API_KEY = defineSecret('REVENUECAT_API_KEY');

// RevenueCat Project ID
// NOTE: Not used with V1 API endpoint (V1 doesn't require project ID)
// const REVENUECAT_PROJECT_ID = 'proj109b9d66';

// ============================================================
// TYPE DEFINITIONS
// ============================================================

type PlanType = 'free' | 'monthly_pro' | 'annual_pro';

interface UserCredits {
  plan: PlanType;
  credits: number;
  maxCredits: number;
  lastMonthlyGrant: admin.firestore.Timestamp;
  createdAt: admin.firestore.Timestamp;
}

interface PlanConfig {
  monthlyCredits: number;
  maxCredits: number;
}

// ============================================================
// PLAN CONFIGURATION
// ============================================================

const PLAN_CONFIG: Record<PlanType, PlanConfig> = {
  free: {
    monthlyCredits: 2,  // Reduced from 5 to drive conversions
    maxCredits: 2,      // Free credits do NOT accumulate
  },
  monthly_pro: {
    monthlyCredits: 50,
    maxCredits: 100,
  },
  annual_pro: {
    monthlyCredits: 50,
    maxCredits: 100, // Same as monthly_pro - annual only provides upfront value
  },
};

// ============================================================
// HELPER FUNCTIONS
// ============================================================

/**
 * Get plan configuration with validation
 */
function getPlanConfig(plan: string): PlanConfig {
  if (plan in PLAN_CONFIG) {
    return PLAN_CONFIG[plan as PlanType];
  }
  // Default to free plan if invalid plan specified
  return PLAN_CONFIG.free;
}

/**
 * Check if a full billing month has passed since last grant
 * Uses 30-day month for simplicity and consistency
 */
function hasMonthPassed(lastGrant: admin.firestore.Timestamp): boolean {
  const now = Date.now();
  const lastGrantMs = lastGrant.toMillis();
  const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
  return now - lastGrantMs >= thirtyDaysMs;
}

/**
 * Verify one-time purchase with RevenueCat API
 * Returns true if the purchase is valid and hasn't been processed before
 *
 * IMPORTANT: Using V1 endpoint for better reliability
 */
async function verifyOneTimePurchase(
  appUserId: string,
  transactionId: string,
  productId: string,
  apiKey: string
): Promise<boolean> {
  // V1 API endpoint - more reliable for customer lookups
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

  const customerData = await response.json();

  // Check if transaction exists in customer's purchase history
  // V1 API stores non-subscription purchases under subscriber.non_subscriptions
  const purchases = customerData.subscriber?.non_subscriptions || {};

  // Verify the product was purchased
  const productPurchases = purchases[productId];
  if (!productPurchases || productPurchases.length === 0) {
    console.error(`No purchase found for product ${productId}`);
    return false;
  }

  // Verify the specific transaction exists
  const transaction = productPurchases.find(
    (p: { id: string }) => p.id === transactionId
  );

  if (!transaction) {
    console.error(`Transaction ${transactionId} not found for product ${productId}`);
    return false;
  }

  return true;
}

// ============================================================
// 1. INITIALIZE USER CREDITS - Callable Function
// ============================================================
/**
 * Initializes credit fields for a new user.
 * Called by Flutter app after user signup/login.
 *
 * This replaces the auth trigger approach to avoid gen1/gen2 conflicts.
 * The function is idempotent - safe to call multiple times.
 *
 * SECURITY:
 * - Requires Firebase Auth
 * - Uses Admin SDK to set credit fields (bypasses Firestore rules)
 * - Only initializes if credits don't exist (prevents reset attacks)
 */
export const initializeUserCredits = onCall(
  {
    memory: '256MiB',
    consumeAppCheckToken: true,
  },
  async (request) => {
    // SECURITY: Require authentication
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'You must be logged in to initialize credits'
      );
    }

    const uid = request.auth.uid;
    const userRef = db.collection('users').doc(uid);

    try {
      const result = await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const userData = userDoc.exists ? userDoc.data() : null;

        // Check if credits are already initialized
        // This prevents malicious users from resetting their credits
        if (userData?.credits !== undefined && userData?.plan !== undefined) {
          console.log(`Credits already initialized for user: ${uid}`);
          return {
            alreadyInitialized: true,
            credits: userData.credits,
            maxCredits: userData.maxCredits,
            plan: userData.plan,
          };
        }

        // Initialize with free plan defaults
        const now = admin.firestore.Timestamp.now();
        const config = getPlanConfig('free');

        const creditData: Partial<UserCredits> = {
          plan: 'free',
          credits: config.monthlyCredits,
          maxCredits: config.maxCredits,
          lastMonthlyGrant: now,
          createdAt: userData?.createdAt || now,
        };

        // Use set with merge to preserve existing profile fields
        transaction.set(userRef, creditData, { merge: true });

        console.log(`Credits initialized for user: ${uid}`);
        return {
          alreadyInitialized: false,
          credits: config.monthlyCredits,
          maxCredits: config.maxCredits,
          plan: 'free',
        };
      });

      return {
        success: true,
        ...result,
      };
    } catch (error) {
      console.error(`Failed to initialize credits for user ${uid}:`, error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError('internal', 'Failed to initialize credits');
    }
  }
);

// ============================================================
// 2. GRANT MONTHLY CREDITS - Scheduled Function
// ============================================================
/**
 * Runs daily at midnight UTC to grant monthly credits.
 *
 * LOGIC:
 * - For each user, check if 30 days have passed since lastMonthlyGrant
 * - If yes, add monthly credits (capped at maxCredits)
 * - Update lastMonthlyGrant timestamp
 *
 * IDEMPOTENCY: Safe to run multiple times - only grants once per cycle
 *
 * SECURITY: Uses Admin SDK - no client can trigger or manipulate this
 */
export const grantMonthlyCredits = onSchedule(
  {
    schedule: '0 0 * * *', // Run daily at midnight UTC
    timeZone: 'UTC',
    retryCount: 3,
    memory: '512MiB',
  },
  async () => {
    console.log('Starting monthly credit grant job');

    try {
      // Get all users - in production, consider pagination for large user bases
      const usersSnapshot = await db.collection('users').get();

      let processedCount = 0;
      let grantedCount = 0;
      let errorCount = 0;

      // Process users in batches for efficiency
      const batch = db.batch();
      let batchCount = 0;
      const MAX_BATCH_SIZE = 500;

      for (const doc of usersSnapshot.docs) {
        processedCount++;

        try {
          const userData = doc.data() as Partial<UserCredits>;

          // Skip if user doesn't have credit fields yet
          // (might happen if onUserCreated failed)
          if (!userData.plan || !userData.lastMonthlyGrant) {
            // Initialize with free plan defaults
            const now = admin.firestore.Timestamp.now();
            const config = getPlanConfig('free');

            batch.set(
              doc.ref,
              {
                plan: 'free',
                credits: config.monthlyCredits,
                maxCredits: config.maxCredits,
                lastMonthlyGrant: now,
                createdAt: userData.createdAt || now,
              } as UserCredits,
              { merge: true }
            );
            batchCount++;
            grantedCount++;
            continue;
          }

          // Skip pro users - they're handled by processSubscriptionRenewals
          // which verifies with RevenueCat before granting credits
          if (userData.plan === 'monthly_pro' || userData.plan === 'annual_pro') {
            continue;
          }

          // Check if month has passed
          if (!hasMonthPassed(userData.lastMonthlyGrant)) {
            continue; // Not yet time for monthly grant
          }

          // Calculate new credit balance
          const config = getPlanConfig(userData.plan);
          const currentCredits = userData.credits ?? 0;

          // Only grant credits if user is below their max
          // This preserves purchased credits that exceed the plan's maxCredits
          if (currentCredits < config.maxCredits) {
            const newCredits = Math.min(
              currentCredits + config.monthlyCredits,
              config.maxCredits
            );

            batch.update(doc.ref, {
              credits: newCredits,
              lastMonthlyGrant: admin.firestore.Timestamp.now(),
            });
          } else {
            // User has more credits than max (from purchases)
            // Just update the grant timer so we don't keep trying
            batch.update(doc.ref, {
              lastMonthlyGrant: admin.firestore.Timestamp.now(),
            });
          }

          batchCount++;
          grantedCount++;

          // Commit batch if it reaches max size
          if (batchCount >= MAX_BATCH_SIZE) {
            await batch.commit();
            batchCount = 0;
          }
        } catch (userError) {
          console.error(`Error processing user ${doc.id}:`, userError);
          errorCount++;
        }
      }

      // Commit any remaining updates
      if (batchCount > 0) {
        await batch.commit();
      }

      console.log(
        `Monthly credit grant complete. ` +
          `Processed: ${processedCount}, Granted: ${grantedCount}, Errors: ${errorCount}`
      );
    } catch (error) {
      console.error('Failed to run monthly credit grant:', error);
      throw error; // Trigger retry
    }
  }
);

// ============================================================
// 3. CONSUME CREDIT - Callable Function
// ============================================================
/**
 * Deducts credits from user's balance before AI generation.
 *
 * INPUT: { amount: number } - Number of credits to consume (usually 1)
 *
 * RETURNS: { success: true, remainingCredits: number }
 *
 * ERRORS:
 * - unauthenticated: User not logged in
 * - resource-exhausted: Insufficient credits
 * - invalid-argument: Invalid amount
 *
 * SECURITY:
 * - Requires Firebase Auth
 * - Uses Firestore transaction for atomic deduction
 * - Client MUST call this before any AI generation
 */
export const consumeCredit = onCall(
  {
    // No secrets needed for this function
    memory: '256MiB',
    consumeAppCheckToken: true,
  },
  async (request) => {
    // SECURITY: Require authentication
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'You must be logged in to use credits'
      );
    }

    const uid = request.auth.uid;
    const { amount } = request.data as { amount?: number };

    // Validate amount
    if (typeof amount !== 'number' || amount <= 0 || !Number.isInteger(amount)) {
      throw new HttpsError(
        'invalid-argument',
        'Amount must be a positive integer'
      );
    }

    // Maximum single deduction to prevent abuse
    if (amount > 10) {
      throw new HttpsError(
        'invalid-argument',
        'Cannot consume more than 10 credits at once'
      );
    }

    const userRef = db.collection('users').doc(uid);

    try {
      // Use transaction for atomic read-check-update
      const result = await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
          throw new HttpsError(
            'not-found',
            'User profile not found. Please try signing out and back in.'
          );
        }

        const userData = userDoc.data() as Partial<UserCredits>;
        const currentCredits = userData.credits ?? 0;

        // Check if user has enough credits
        if (currentCredits < amount) {
          throw new HttpsError(
            'resource-exhausted',
            `Insufficient credits. You have ${currentCredits} credits but need ${amount}.`
          );
        }

        // Deduct credits atomically
        const newCredits = currentCredits - amount;
        transaction.update(userRef, { credits: newCredits });

        return { remainingCredits: newCredits };
      });

      console.log(
        `User ${uid} consumed ${amount} credit(s). Remaining: ${result.remainingCredits}`
      );

      return {
        success: true,
        remainingCredits: result.remainingCredits,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error(`Error consuming credit for user ${uid}:`, error);
      throw new HttpsError('internal', 'Failed to consume credit');
    }
  }
);

// ============================================================
// 4. SET USER PLAN - Callable Function
// ============================================================
/**
 * Updates user's subscription plan after App Store / Play Store validation.
 *
 * INPUT: { plan: 'free' | 'monthly_pro' | 'annual_pro' }
 *
 * LOGIC:
 * - Updates plan and maxCredits
 * - Does NOT auto-fill credits (governed by monthly grant + cap)
 * - If upgrading and current credits > 0, they're preserved
 *
 * SECURITY:
 * - Requires Firebase Auth
 * - In production, this should be called ONLY after validating
 *   the purchase receipt with Apple/Google servers
 * - Consider adding server-side receipt validation here
 *
 * NOTE: For production, you should validate the purchase receipt
 * before calling this function. Consider using:
 * - Apple: App Store Server API
 * - Google: Google Play Developer API
 */
export const setUserPlan = onCall(
  {
    memory: '256MiB',
    consumeAppCheckToken: true,
  },
  async (request) => {
    // SECURITY: Require authentication
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'You must be logged in to update your plan'
      );
    }

    const uid = request.auth.uid;
    const { plan } = request.data as { plan?: string };

    // Validate plan
    const validPlans: PlanType[] = ['free', 'monthly_pro', 'annual_pro'];
    if (!plan || !validPlans.includes(plan as PlanType)) {
      throw new HttpsError(
        'invalid-argument',
        `Invalid plan. Must be one of: ${validPlans.join(', ')}`
      );
    }

    const userRef = db.collection('users').doc(uid);
    const config = getPlanConfig(plan);

    try {
      await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
          throw new HttpsError(
            'not-found',
            'User profile not found. Please try signing out and back in.'
          );
        }

        const userData = userDoc.data() as Partial<UserCredits>;
        const currentCredits = userData.credits ?? 0;

        // Update plan and maxCredits
        // Credits remain unchanged (governed by monthly grant)
        // However, if current credits exceed new maxCredits, cap them
        const newCredits = Math.min(currentCredits, config.maxCredits);

        transaction.update(userRef, {
          plan: plan as PlanType,
          maxCredits: config.maxCredits,
          credits: newCredits, // Cap if needed, but don't auto-fill
        });
      });

      console.log(`User ${uid} plan updated to: ${plan}`);

      return {
        success: true,
        plan: plan,
        maxCredits: config.maxCredits,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error(`Error updating plan for user ${uid}:`, error);
      throw new HttpsError('internal', 'Failed to update plan');
    }
  }
);

// ============================================================
// 5. GET USER CREDITS - Callable Function (Optional Helper)
// ============================================================
/**
 * Returns the user's current credit balance and plan info.
 *
 * This is a convenience function - clients can also read directly
 * from Firestore (which is allowed by security rules).
 *
 * Useful for:
 * - Ensuring fresh data (bypasses any client-side cache)
 * - Getting credit info in contexts where Firestore isn't available
 */
export const getUserCredits = onCall(
  {
    memory: '256MiB',
    consumeAppCheckToken: true,
  },
  async (request) => {
    // SECURITY: Require authentication
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'You must be logged in to view credits'
      );
    }

    const uid = request.auth.uid;
    const userRef = db.collection('users').doc(uid);

    try {
      const userDoc = await userRef.get();

      if (!userDoc.exists) {
        throw new HttpsError(
          'not-found',
          'User profile not found. Please try signing out and back in.'
        );
      }

      const userData = userDoc.data() as Partial<UserCredits>;

      return {
        credits: userData.credits ?? 0,
        maxCredits: userData.maxCredits ?? 5,
        plan: userData.plan ?? 'free',
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error(`Error getting credits for user ${uid}:`, error);
      throw new HttpsError('internal', 'Failed to get credit info');
    }
  }
);

// ============================================================
// 6. HANDLE CREDIT TOP-UP - Callable Function
// ============================================================
/**
 * Handles credit top-up purchases (15 credits for $4.99).
 * Available for ALL users (including free tier).
 *
 * INPUT: {
 *   productId: string,        // RevenueCat product identifier (topup_stylecredits)
 *   transactionId: string     // RevenueCat transaction ID from SDK
 * }
 *
 * RETURNS: { success: true, creditsAdded: number, newBalance: number }
 *
 * ERRORS:
 * - unauthenticated: User not logged in
 * - invalid-argument: Invalid product ID or missing transaction ID
 * - already-exists: Transaction already processed
 * - failed-precondition: Purchase verification failed
 *
 * SECURITY:
 * - Requires Firebase Auth
 * - Available to ALL users (free and pro)
 * - Verifies purchase with RevenueCat API
 * - Prevents duplicate processing via transaction tracking
 * - Uses Firestore transaction for atomic addition
 * - Purchased credits NEVER expire - preserved even on free tier
 *
 * IMPORTANT: Purchased credits are NOT capped for free users.
 * Free users keep all purchased credits even though their maxCredits is 2.
 * The grantMonthlyCredits function respects this by never reducing credits.
 */
export const handleCreditTopUp = onCall(
  {
    memory: '256MiB',
    secrets: [REVENUECAT_API_KEY],
    consumeAppCheckToken: true,
  },
  async (request) => {
    // SECURITY: Require authentication
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'You must be logged in to purchase credits'
      );
    }

    const uid = request.auth.uid;
    const { productId, transactionId } = request.data as {
      productId?: string;
      transactionId?: string;
    };

    // Validate product ID - must match RevenueCat product identifier
    if (!productId || productId !== 'stylecredits_15pack') {
      throw new HttpsError(
        'invalid-argument',
        'Invalid credit top-up product ID'
      );
    }

    // Validate transaction ID
    if (!transactionId || typeof transactionId !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        'Transaction ID is required for purchase verification'
      );
    }

    console.log(`Processing top-up for user ${uid}, transaction: ${transactionId}`);

    const userRef = db.collection('users').doc(uid);
    const transactionRef = db.collection('processedTransactions').doc(transactionId);
    const CREDITS_TO_ADD = 15;

    try {
      // Check if transaction was already processed (prevent replay attacks)
      const existingTransaction = await transactionRef.get();
      if (existingTransaction.exists) {
        console.error(`Transaction ${transactionId} already processed`);
        throw new HttpsError(
          'already-exists',
          'This purchase has already been processed. If you believe this is an error, please contact support.'
        );
      }

      // Verify purchase with RevenueCat API
      const isValid = await verifyOneTimePurchase(
        uid,
        transactionId,
        productId,
        REVENUECAT_API_KEY.value()
      );

      if (!isValid) {
        console.error(`Purchase verification failed for transaction ${transactionId}`);
        throw new HttpsError(
          'failed-precondition',
          'Purchase verification failed. Please try again or contact support.'
        );
      }

      // Process the credit top-up
      const result = await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
          throw new HttpsError(
            'not-found',
            'User profile not found. Please try signing out and back in.'
          );
        }

        const userData = userDoc.data() as Partial<UserCredits>;
        const currentCredits = userData.credits ?? 0;

        // IMPORTANT: Purchased credits are NOT capped
        // Free users can accumulate purchased credits beyond their maxCredits of 2
        // The grantMonthlyCredits function respects this and never reduces credits
        const newCredits = currentCredits + CREDITS_TO_ADD;
        const actualCreditsAdded = CREDITS_TO_ADD;

        // Update credits atomically
        transaction.update(userRef, { credits: newCredits });

        // Mark transaction as processed
        transaction.set(transactionRef, {
          uid: uid,
          productId: productId,
          transactionId: transactionId,
          creditsGranted: actualCreditsAdded,
          processedAt: admin.firestore.Timestamp.now(),
        });

        return {
          creditsAdded: actualCreditsAdded,
          newBalance: newCredits,
          previousBalance: currentCredits,
        };
      });

      console.log(
        `User ${uid} purchased credit top-up. ` +
          `Added ${result.creditsAdded} credits. ` +
          `Balance: ${result.previousBalance} → ${result.newBalance}`
      );

      return {
        success: true,
        creditsAdded: result.creditsAdded,
        newBalance: result.newBalance,
        message: `Added ${result.creditsAdded} credits successfully`,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error(`Error processing credit top-up for user ${uid}:`, error);
      throw new HttpsError('internal', 'Failed to process credit top-up');
    }
  }
);

/**
 * handleCreditTopUp5Pack - Grant 5 style credits for one-time $2.99 purchase
 *
 * This is a SEPARATE function from handleCreditTopUp to avoid interfering
 * with the existing 15-pack purchases in production.
 *
 * Security:
 * - Requires Firebase authentication
 * - Validates purchase with RevenueCat API
 * - Prevents duplicate processing via transaction tracking
 * - Uses Firestore transaction for atomic addition
 * - Purchased credits NEVER expire - preserved even on free tier
 */
export const handleCreditTopUp5Pack = onCall(
  {
    memory: '256MiB',
    secrets: [REVENUECAT_API_KEY],
    consumeAppCheckToken: true,
  },
  async (request) => {
    // SECURITY: Require authentication
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'You must be logged in to purchase credits'
      );
    }

    const uid = request.auth.uid;
    const { productId, transactionId } = request.data as {
      productId?: string;
      transactionId?: string;
    };

    // Validate product ID - 5-pack specific, must match RevenueCat product identifier
    if (!productId || productId !== 'stylecredits_5pack') {
      throw new HttpsError(
        'invalid-argument',
        'Invalid credit top-up product ID for 5-pack'
      );
    }

    // Validate transaction ID
    if (!transactionId || typeof transactionId !== 'string') {
      throw new HttpsError(
        'invalid-argument',
        'Transaction ID is required for purchase verification'
      );
    }

    console.log(`Processing 5-pack top-up for user ${uid}, transaction: ${transactionId}`);

    const userRef = db.collection('users').doc(uid);
    const transactionRef = db.collection('processedTransactions').doc(transactionId);
    const CREDITS_TO_ADD = 5; // 5-pack grants 5 credits

    try {
      // Check if transaction was already processed (prevent replay attacks)
      const existingTransaction = await transactionRef.get();
      if (existingTransaction.exists) {
        console.error(`Transaction ${transactionId} already processed`);
        throw new HttpsError(
          'already-exists',
          'This purchase has already been processed. If you believe this is an error, please contact support.'
        );
      }

      // Verify purchase with RevenueCat API
      const isValid = await verifyOneTimePurchase(
        uid,
        transactionId,
        productId,
        REVENUECAT_API_KEY.value()
      );

      if (!isValid) {
        console.error(`Purchase verification failed for 5-pack transaction ${transactionId}`);
        throw new HttpsError(
          'failed-precondition',
          'Purchase verification failed. Please try again or contact support.'
        );
      }

      // Process the credit top-up
      const result = await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
          throw new HttpsError(
            'not-found',
            'User profile not found. Please try signing out and back in.'
          );
        }

        const userData = userDoc.data() as Partial<UserCredits>;
        const currentCredits = userData.credits ?? 0;

        // IMPORTANT: Purchased credits are NOT capped
        // Free users can accumulate purchased credits beyond their maxCredits of 2
        const newCredits = currentCredits + CREDITS_TO_ADD;
        const actualCreditsAdded = CREDITS_TO_ADD;

        // Update credits atomically
        transaction.update(userRef, { credits: newCredits });

        // Mark transaction as processed
        transaction.set(transactionRef, {
          uid: uid,
          productId: productId,
          transactionId: transactionId,
          creditsGranted: actualCreditsAdded,
          processedAt: admin.firestore.Timestamp.now(),
        });

        return {
          creditsAdded: actualCreditsAdded,
          newBalance: newCredits,
          previousBalance: currentCredits,
        };
      });

      console.log(
        `User ${uid} purchased 5-pack credit top-up. ` +
          `Added ${result.creditsAdded} credits. ` +
          `Balance: ${result.previousBalance} → ${result.newBalance}`
      );

      return {
        success: true,
        creditsAdded: result.creditsAdded,
        newBalance: result.newBalance,
        message: `Added ${result.creditsAdded} credits successfully`,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      console.error(`Error processing 5-pack credit top-up for user ${uid}:`, error);
      throw new HttpsError('internal', 'Failed to process credit top-up');
    }
  }
);
