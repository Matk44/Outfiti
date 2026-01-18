/**
 * Firebase Auth Triggers
 *
 * Server-side safety net that automatically creates Firestore user documents
 * when new Firebase Auth accounts are created.
 *
 * This ensures users ALWAYS have Firestore documents, even if the app-side
 * initialization fails due to race conditions or network issues.
 *
 * BACKWARD COMPATIBILITY:
 * - This trigger only fires for NEW user signups
 * - It does NOT affect existing users
 * - If app-side code also creates the document, this trigger safely skips
 * - Old app versions benefit from this too (server creates doc before app tries)
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// Initialize admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * Triggered when a new user is created in Firebase Auth.
 *
 * Creates a Firestore user document with all required fields including:
 * - Profile fields (uid, email, displayName, etc.)
 * - Credit system fields (plan, credits, maxCredits)
 * - Timestamps
 *
 * Uses a Firestore transaction to ensure atomic read-modify-write,
 * preventing race conditions with app-side profile initialization.
 *
 * This is idempotent - if the document already exists (created by app),
 * it will only add missing credit fields.
 */
export const onUserCreated = functions
  .runWith({
    memory: '256MB',
    timeoutSeconds: 60,
  })
  .auth.user()
  .onCreate(async (user) => {
    const uid = user.uid;
    console.log(`Auth trigger: New user created: ${uid} (${user.email || 'no email'})`);

    try {
      const userRef = db.collection('users').doc(uid);

      // Use transaction for atomic read-modify-write
      // This prevents race conditions with app-side initialization
      await db.runTransaction(async (transaction) => {
        const doc = await transaction.get(userRef);

        if (doc.exists) {
          // Document already exists (app created it faster, or restored user)
          console.log(`Auth trigger: User doc already exists for ${uid}, checking completeness`);

          // Check if credits are initialized - if not, add them
          const data = doc.data();
          if (data && data.credits === undefined) {
            transaction.update(userRef, {
              plan: 'free',
              credits: 2,
              maxCredits: 2,
              lastMonthlyGrant: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`Auth trigger: Added missing credits to ${uid}`);
          }

          return;
        }

        // Create user document with all required fields
        transaction.set(userRef, {
          // Profile fields
          uid: uid,
          email: user.email || '',
          displayName: user.displayName || '',
          profileImageUrl: user.photoURL || '',
          selectedTheme: 'Divine Gold',
          os: 'unknown',  // Can't determine from server

          // Credit system fields (free tier defaults)
          plan: 'free',
          credits: 2,
          maxCredits: 2,
          lastMonthlyGrant: admin.firestore.FieldValue.serverTimestamp(),

          // Timestamps
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          lastLoginTime: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`Auth trigger: Created user doc for ${uid}`);
      });

    } catch (error) {
      // Log error but don't throw - we don't want to block user creation
      // The app-side code or backfill can recover this
      console.error(`Auth trigger: Error creating user doc for ${uid}:`, error);
    }
  });
