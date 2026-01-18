/**
 * Backfill Missing User Documents
 *
 * One-time migration script to create Firestore documents for all Firebase Auth
 * users who are missing their user profile documents.
 *
 * This is safe to run multiple times - it will skip users who already have documents.
 *
 * Usage:
 * 1. Deploy: firebase deploy --only functions:backfillMissingUsers
 * 2. Run via Firebase Console or functions:shell
 */

import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

// Initialize admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const auth = admin.auth();

/**
 * Admin-only callable function to backfill missing user documents.
 *
 * This function iterates through ALL Firebase Auth users and creates
 * Firestore documents for any users missing them.
 *
 * Security: This function should only be called by administrators.
 * Consider adding admin check in production.
 */
export const backfillMissingUsers = onCall(
  {
    memory: '512MiB',
    timeoutSeconds: 540,  // 9 minutes max
  },
  async (request) => {
    // Log who triggered this (for audit)
    const callerUid = request.auth?.uid || 'anonymous';
    console.log(`backfillMissingUsers triggered by: ${callerUid}`);

    let nextPageToken: string | undefined;
    let created = 0;
    let skipped = 0;
    let errors = 0;
    const errorDetails: Array<{uid: string; error: string}> = [];

    try {
      do {
        // List Firebase Auth users (1000 at a time - max batch size)
        const listResult = await auth.listUsers(1000, nextPageToken);
        console.log(`Processing batch of ${listResult.users.length} users...`);

        for (const user of listResult.users) {
          try {
            const userRef = db.collection('users').doc(user.uid);
            const doc = await userRef.get();

            if (!doc.exists) {
              // Create missing user document with all required fields
              await userRef.set({
                // Profile fields
                uid: user.uid,
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

              created++;
              console.log(`Created doc for user: ${user.uid} (${user.email || 'no email'})`);
            } else {
              // Document exists - check if it has credits initialized
              const data = doc.data();
              if (data && data.credits === undefined) {
                // Document exists but credits not initialized - add them
                await userRef.update({
                  plan: 'free',
                  credits: 2,
                  maxCredits: 2,
                  lastMonthlyGrant: admin.firestore.FieldValue.serverTimestamp(),
                });
                console.log(`Added credits to existing user: ${user.uid}`);
                created++;  // Count as a fix
              } else {
                skipped++;
              }
            }
          } catch (error) {
            errors++;
            const errorMsg = error instanceof Error ? error.message : String(error);
            errorDetails.push({ uid: user.uid, error: errorMsg });
            console.error(`Error processing user ${user.uid}:`, error);
          }
        }

        nextPageToken = listResult.pageToken;
      } while (nextPageToken);

      console.log(`Backfill complete: created=${created}, skipped=${skipped}, errors=${errors}`);

      return {
        success: true,
        created,
        skipped,
        errors,
        errorDetails: errorDetails.slice(0, 10),  // Return first 10 errors
      };

    } catch (error) {
      console.error('Backfill failed:', error);
      throw new HttpsError(
        'internal',
        `Backfill failed: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }
);
