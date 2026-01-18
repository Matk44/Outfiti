/**
 * Rate Limiting Utility for AI Image Generation
 *
 * SECURITY: All rate limiting is enforced server-side in Cloud Functions.
 * This module provides atomic operations to:
 * - Enforce minimum time between generations (15-20 seconds cooldown)
 * - Limit concurrent generations per user (max 3)
 * - Safely consume credits only on successful generation
 *
 * Firestore Schema (users/{uid}):
 * - lastGenerationAt: Timestamp - Last successful generation time
 * - activeGenerations: number - Count of currently running generations
 * - credits: number - User's available style credits
 */

import * as admin from 'firebase-admin';
import { HttpsError } from 'firebase-functions/v2/https';

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// ============================================================
// CONFIGURATION
// ============================================================

/** Minimum seconds between generation requests (cooldown period) */
const MIN_GENERATION_INTERVAL_SECONDS = 15;

/** Maximum concurrent generations allowed per user */
const MAX_CONCURRENT_GENERATIONS = 3;

// ============================================================
// TYPES
// ============================================================

export interface RateLimitResult {
  /** Whether the user passed rate limit checks */
  allowed: boolean;
  /** Error message if not allowed */
  errorMessage?: string;
  /** Error code for client handling */
  errorCode?: 'cooldown' | 'concurrent_limit' | 'insufficient_credits';
  /** Seconds until next allowed generation (for cooldown) */
  retryAfterSeconds?: number;
}

export interface GenerationContext {
  /** User's Firebase Auth UID */
  uid: string;
  /** Number of credits to consume (usually 1) */
  creditsToConsume: number;
  /** Reference to user document */
  userRef: admin.firestore.DocumentReference;
}

// ============================================================
// RATE LIMIT CHECK & ACQUIRE SLOT
// ============================================================

/**
 * Check rate limits and acquire a generation slot atomically.
 *
 * This function performs the following in a Firestore transaction:
 * 1. Check if enough time has passed since lastGenerationAt (15s cooldown)
 * 2. Check if user has available generation slots (max 3 concurrent)
 * 3. Check if user has enough credits
 * 4. If all checks pass, increment activeGenerations counter
 *
 * IMPORTANT: Caller MUST call releaseGenerationSlot() after generation completes
 * (success or failure) to decrement the counter and prevent stuck state.
 *
 * @param uid - User's Firebase Auth UID
 * @param creditsRequired - Number of credits needed (usually 1)
 * @returns GenerationContext if allowed, throws HttpsError if rate limited
 */
export async function acquireGenerationSlot(
  uid: string,
  creditsRequired: number = 1
): Promise<GenerationContext> {
  const userRef = db.collection('users').doc(uid);

  try {
    await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);

      if (!userDoc.exists) {
        throw new HttpsError(
          'not-found',
          'User profile not found. Please try signing out and back in.'
        );
      }

      const userData = userDoc.data()!;
      const now = admin.firestore.Timestamp.now();
      const currentCredits = userData.credits ?? 0;
      const activeGenerations = userData.activeGenerations ?? 0;
      const lastGenerationAt = userData.lastGenerationAt as admin.firestore.Timestamp | undefined;

      // --------------------------------------------------------
      // CHECK 1: Cooldown period (minimum time between generations)
      // --------------------------------------------------------
      if (lastGenerationAt) {
        const elapsedSeconds = (now.toMillis() - lastGenerationAt.toMillis()) / 1000;
        const remainingCooldown = Math.ceil(MIN_GENERATION_INTERVAL_SECONDS - elapsedSeconds);

        if (elapsedSeconds < MIN_GENERATION_INTERVAL_SECONDS) {
          console.log(
            `Rate limit: User ${uid} cooldown not elapsed. ` +
            `Elapsed: ${elapsedSeconds.toFixed(1)}s, Required: ${MIN_GENERATION_INTERVAL_SECONDS}s`
          );
          throw new HttpsError(
            'resource-exhausted',
            `Please wait a moment before generating again`,
            { errorCode: 'cooldown', retryAfterSeconds: remainingCooldown }
          );
        }
      }

      // --------------------------------------------------------
      // CHECK 2: Concurrent generation limit
      // --------------------------------------------------------
      if (activeGenerations >= MAX_CONCURRENT_GENERATIONS) {
        console.log(
          `Rate limit: User ${uid} has ${activeGenerations} active generations (max: ${MAX_CONCURRENT_GENERATIONS})`
        );
        throw new HttpsError(
          'resource-exhausted',
          'Too many requests in progress',
          { errorCode: 'concurrent_limit' }
        );
      }

      // --------------------------------------------------------
      // CHECK 3: Credit availability
      // --------------------------------------------------------
      if (currentCredits < creditsRequired) {
        console.log(
          `Rate limit: User ${uid} has ${currentCredits} credits, needs ${creditsRequired}`
        );
        throw new HttpsError(
          'resource-exhausted',
          `Insufficient credits. You have ${currentCredits} credits but need ${creditsRequired}.`,
          { errorCode: 'insufficient_credits', currentCredits }
        );
      }

      // --------------------------------------------------------
      // ALL CHECKS PASSED: Acquire generation slot
      // --------------------------------------------------------
      // Increment activeGenerations counter (will be decremented after generation)
      // NOTE: We do NOT consume credits here - only after successful generation
      transaction.update(userRef, {
        activeGenerations: admin.firestore.FieldValue.increment(1),
      });

      console.log(
        `Rate limit: User ${uid} acquired generation slot. ` +
        `Active: ${activeGenerations + 1}/${MAX_CONCURRENT_GENERATIONS}`
      );
    });

    return {
      uid,
      creditsToConsume: creditsRequired,
      userRef,
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error(`Error acquiring generation slot for user ${uid}:`, error);
    throw new HttpsError('internal', 'Failed to process request. Please try again.');
  }
}

// ============================================================
// RELEASE GENERATION SLOT
// ============================================================

/**
 * Release a generation slot after generation completes.
 *
 * This MUST be called after generation completes (success or failure)
 * to decrement the activeGenerations counter and prevent stuck state.
 *
 * @param context - The GenerationContext returned by acquireGenerationSlot
 * @param success - Whether the generation was successful
 */
export async function releaseGenerationSlot(
  context: GenerationContext,
  success: boolean
): Promise<{ remainingCredits?: number }> {
  const { uid, creditsToConsume, userRef } = context;

  try {
    const result = await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);

      if (!userDoc.exists) {
        // User was deleted? Just log and continue
        console.warn(`User ${uid} document not found when releasing slot`);
        return { remainingCredits: undefined };
      }

      const userData = userDoc.data()!;
      const currentCredits = userData.credits ?? 0;
      const activeGenerations = userData.activeGenerations ?? 0;

      // Calculate new values
      // Always decrement activeGenerations (min 0 to prevent negative)
      const newActiveGenerations = Math.max(0, activeGenerations - 1);

      // Only consume credits if generation was successful
      let newCredits = currentCredits;
      if (success) {
        newCredits = Math.max(0, currentCredits - creditsToConsume);
      }

      // Update atomically
      const updateData: Record<string, unknown> = {
        activeGenerations: newActiveGenerations,
      };

      if (success) {
        // Only update credits and lastGenerationAt on success
        updateData.credits = newCredits;
        updateData.lastGenerationAt = admin.firestore.Timestamp.now();
        console.log(
          `Generation success: User ${uid} consumed ${creditsToConsume} credit(s). ` +
          `Remaining: ${newCredits}, Active generations: ${newActiveGenerations}`
        );
      } else {
        console.log(
          `Generation failed: User ${uid} - credits NOT consumed. ` +
          `Current: ${currentCredits}, Active generations: ${newActiveGenerations}`
        );
      }

      transaction.update(userRef, updateData);

      return { remainingCredits: newCredits };
    });

    return result;
  } catch (error) {
    // Log error but don't throw - we don't want to mask the original error
    console.error(
      `Error releasing generation slot for user ${uid}:`,
      error
    );
    return { remainingCredits: undefined };
  }
}

// ============================================================
// WRAPPER FOR SAFE GENERATION EXECUTION
// ============================================================

/**
 * Execute a generation function with rate limiting and credit protection.
 *
 * This wrapper handles:
 * 1. Acquiring a generation slot (with all rate limit checks)
 * 2. Executing the provided generation function
 * 3. Releasing the slot and consuming credits only on success
 * 4. Ensuring the slot is always released (even on error)
 *
 * @param uid - User's Firebase Auth UID
 * @param creditsRequired - Number of credits to consume on success
 * @param generationFn - The actual generation function to execute
 * @returns The result of the generation function
 *
 * @example
 * ```typescript
 * const result = await executeWithRateLimiting(
 *   request.auth.uid,
 *   1, // 1 credit
 *   async () => {
 *     // Your actual AI generation logic here
 *     const response = await callAIApi(...);
 *     return { imageBase64: response.image };
 *   }
 * );
 * ```
 */
export async function executeWithRateLimiting<T>(
  uid: string,
  creditsRequired: number,
  generationFn: () => Promise<T>
): Promise<T & { remainingCredits?: number }> {
  // Step 1: Acquire generation slot (throws HttpsError if rate limited)
  const context = await acquireGenerationSlot(uid, creditsRequired);

  let success = false;
  let result: T | undefined;
  let caughtError: Error | undefined;

  try {
    // Step 2: Execute the actual generation
    result = await generationFn();
    success = true;
  } catch (error) {
    // Capture the error to rethrow after releasing the slot
    caughtError = error instanceof Error ? error : new Error(String(error));
    success = false;
  }

  // Step 3: Always release the slot (success or failure)
  const releaseResult = await releaseGenerationSlot(context, success);

  // If generation failed, rethrow the original error
  if (caughtError) {
    throw caughtError;
  }

  // If we have a result and success, attach remaining credits
  if (success && result !== undefined) {
    (result as T & { remainingCredits?: number }).remainingCredits =
      releaseResult.remainingCredits;
  }

  return result as T & { remainingCredits?: number };
}

// ============================================================
// UTILITY: RESET STUCK COUNTERS (Admin use only)
// ============================================================

/**
 * Reset activeGenerations counter for a user.
 *
 * This should only be used by admin functions to fix stuck counters
 * (e.g., if a Cloud Function times out without releasing the slot).
 *
 * In production, consider running a scheduled function to detect and
 * reset counters that have been stuck for too long.
 *
 * @param uid - User's Firebase Auth UID
 */
export async function resetActiveGenerations(uid: string): Promise<void> {
  const userRef = db.collection('users').doc(uid);

  await userRef.update({
    activeGenerations: 0,
  });

  console.log(`Admin: Reset activeGenerations for user ${uid}`);
}
