/**
 * Firebase Cloud Functions for Outfiti
 *
 * These functions proxy requests to the laozhang.ai API, keeping the API key
 * secure on the server side. All functions require authentication.
 *
 * RATE LIMITING & CREDIT PROTECTION:
 * - All generation functions use server-side rate limiting
 * - 15-second cooldown between generations per user
 * - Maximum 3 concurrent generations per user
 * - Credits are only consumed on successful generation
 * - All limits enforced atomically via Firestore transactions
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import fetch from 'node-fetch';
import { OUTFIT_PROMPT, buildStyleChangePrompt, buildDescribePrompt } from './prompts';
import { mapToSupportedAspectRatio } from './utils';
import { executeWithRateLimiting } from './rate-limiter';

// ============================================================
// CREDIT SYSTEM EXPORTS
// ============================================================
// Export all credit-related functions from the credits module
// See credits.ts for implementation details and security documentation
export {
  initializeUserCredits,
  grantMonthlyCredits,
  consumeCredit,
  setUserPlan,
  getUserCredits,
  handleCreditTopUp,
  handleCreditTopUp5Pack,
} from './credits';

// ============================================================
// REVENUECAT PURCHASE & SUBSCRIPTION EXPORTS
// ============================================================
// Handle purchases, restores, and subscription renewals
// See purchase.ts and subscription-credits.ts for details
export { handlePurchaseSuccess, handleRestorePurchase } from './purchase';
export { processSubscriptionRenewals } from './subscription-credits';

// ============================================================
// USER INITIALIZATION & BACKFILL EXPORTS
// ============================================================
// Server-side safety net for user document creation
// See auth-triggers.ts and backfill-users.ts for details
export { onUserCreated } from './auth-triggers';
export { backfillMissingUsers } from './backfill-users';

// Define the secret for the API key (stored in Secret Manager)
const laozhangApiKey = defineSecret('LAOZHANG_API_KEY');

// API configuration - Google Native Format for aspect ratio control
const API_URL = 'https://api.laozhang.ai/v1beta/models/gemini-3-pro-image-preview:generateContent';

// Common function options
const functionOptions = {
  timeoutSeconds: 300, // 5 minutes for AI image generation
  memory: '1GiB' as const,
  secrets: [laozhangApiKey],
  // enforceAppCheck: true, // Reject requests with missing or invalid App Check tokens
  // TODO: Re-enable App Check after testing
};

// Google Native Format response interface
interface ApiResponse {
  candidates?: Array<{
    content?: {
      parts?: Array<{
        inlineData?: {
          data: string;
        };
      }>;
    };
  }>;
}

/**
 * Generate outfit by transplanting reference outfit onto selfie
 *
 * RATE LIMITING:
 * - 15-second cooldown between generations
 * - Maximum 3 concurrent generations per user
 * - Credits only consumed on successful generation
 *
 * @param selfieBase64 - Base64 encoded selfie image
 * @param referenceBase64 - Base64 encoded reference outfit image
 * @returns Object with imageBase64 and remainingCredits
 */
export const generateOutfit = onCall(functionOptions, async (request) => {
  // Require authentication
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in to generate outfits');
  }

  const uid = request.auth.uid;
  const { selfieBase64, referenceBase64, aspectRatio } = request.data as {
    selfieBase64?: string;
    referenceBase64?: string;
    aspectRatio?: number;
  };

  // Validate inputs BEFORE rate limiting (fast fail)
  if (!selfieBase64 || !referenceBase64) {
    throw new HttpsError('invalid-argument', 'Missing required images: selfieBase64 and referenceBase64');
  }

  // Validate base64 strings are reasonable size (prevent abuse)
  const maxImageSize = 10 * 1024 * 1024; // 10MB
  if (selfieBase64.length > maxImageSize || referenceBase64.length > maxImageSize) {
    throw new HttpsError('invalid-argument', 'Image size exceeds maximum allowed (10MB)');
  }

  // Map aspect ratio to supported value (default to 3:4 portrait if not provided)
  const aspectRatioStr = aspectRatio
    ? mapToSupportedAspectRatio(aspectRatio)
    : "3:4";

  // Execute with rate limiting and credit protection
  // Credits are ONLY consumed if generation succeeds
  return executeWithRateLimiting(uid, 1, async () => {
    // Google Native Format payload
    const payload = {
      contents: [{
        parts: [
          { text: OUTFIT_PROMPT },
          {
            inline_data: {
              mime_type: 'image/jpeg',
              data: selfieBase64
            }
          },
          {
            inline_data: {
              mime_type: 'image/jpeg',
              data: referenceBase64
            }
          }
        ]
      }],
      generationConfig: {
        responseModalities: ["IMAGE"],
        imageConfig: {
          aspectRatio: aspectRatioStr,
          imageSize: "2K"  // Higher quality than default 1K
        }
      }
    };

    const response = await fetch(API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${laozhangApiKey.value().trim()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('API error:', response.status, errorText);
      throw new HttpsError('internal', `API request failed: ${response.status}`);
    }

    const result = await response.json() as ApiResponse;

    // Extract image from Google Native Format response
    const imageData = result.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;

    if (!imageData) {
      console.error('Could not extract image from response:', JSON.stringify(result).substring(0, 500));
      throw new HttpsError('internal', 'Could not extract image from API response');
    }

    return { imageBase64: imageData };
  });
});

/**
 * AI Try-On with multiple clothing items
 *
 * Allows users to upload their photo and up to 6 clothing item images to virtually
 * try on the outfit.
 *
 * RATE LIMITING:
 * - 15-second cooldown between generations
 * - Maximum 3 concurrent generations per user
 * - Credits only consumed on successful generation
 *
 * @param selfieBase64 - Base64 encoded selfie image
 * @param clothingItemsBase64 - Array of base64 encoded clothing item images (1-6 items)
 * @returns Object with imageBase64 and remainingCredits
 */
export const changeOutfitStyle = onCall(functionOptions, async (request) => {
  // Require authentication
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in to change outfit style');
  }

  const uid = request.auth.uid;
  const { selfieBase64, clothingItemsBase64, aspectRatio } = request.data as {
    selfieBase64?: string;
    clothingItemsBase64?: string[];
    aspectRatio?: number;
  };

  // Validate inputs BEFORE rate limiting (fast fail)
  if (!selfieBase64) {
    throw new HttpsError('invalid-argument', 'Missing required data: selfieBase64');
  }

  if (!clothingItemsBase64 || !Array.isArray(clothingItemsBase64) || clothingItemsBase64.length === 0) {
    throw new HttpsError('invalid-argument', 'At least one clothing item is required');
  }

  // Validate number of clothing items (max 6)
  if (clothingItemsBase64.length > 6) {
    throw new HttpsError('invalid-argument', 'Maximum 6 clothing items allowed');
  }

  // Validate base64 string sizes
  const maxImageSize = 10 * 1024 * 1024; // 10MB
  if (selfieBase64.length > maxImageSize) {
    throw new HttpsError('invalid-argument', 'Selfie image size exceeds maximum allowed (10MB)');
  }

  for (let i = 0; i < clothingItemsBase64.length; i++) {
    if (clothingItemsBase64[i].length > maxImageSize) {
      throw new HttpsError('invalid-argument', `Clothing item ${i + 1} size exceeds maximum allowed (10MB)`);
    }
  }

  // Map aspect ratio to supported value (default to 3:4 portrait if not provided)
  const aspectRatioStr = aspectRatio
    ? mapToSupportedAspectRatio(aspectRatio)
    : "3:4";

  // Execute with rate limiting and credit protection
  // Credits are ONLY consumed if generation succeeds
  return executeWithRateLimiting(uid, 1, async () => {
    // Build parts array with prompt, user image, and all clothing items (Google Native Format)
    const parts: Array<Record<string, unknown>> = [
      { text: buildStyleChangePrompt('') },
      {
        inline_data: {
          mime_type: 'image/jpeg',
          data: selfieBase64
        }
      }
    ];

    // Add all clothing item images
    for (const clothingItemBase64 of clothingItemsBase64) {
      parts.push({
        inline_data: {
          mime_type: 'image/jpeg',
          data: clothingItemBase64
        }
      });
    }

    // Google Native Format payload
    const payload = {
      contents: [{
        parts: parts
      }],
      generationConfig: {
        responseModalities: ["IMAGE"],
        imageConfig: {
          aspectRatio: aspectRatioStr,
          imageSize: "2K"  // Higher quality than default 1K
        }
      }
    };

    const response = await fetch(API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${laozhangApiKey.value().trim()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('API error:', response.status, errorText);
      throw new HttpsError('internal', `API request failed: ${response.status}`);
    }

    const result = await response.json() as ApiResponse;

    // Extract image from Google Native Format response
    const imageData = result.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;

    if (!imageData) {
      console.error('Could not extract image from response:', JSON.stringify(result).substring(0, 500));
      throw new HttpsError('internal', 'Could not extract image from API response');
    }

    return { imageBase64: imageData };
  });
});

/**
 * Generate outfit from text description
 *
 * RATE LIMITING:
 * - 15-second cooldown between generations
 * - Maximum 3 concurrent generations per user
 * - Credits only consumed on successful generation
 *
 * @param selfieBase64 - Base64 encoded selfie image
 * @param userDescription - Text description of desired outfit
 * @param targetColor - (OPTIONAL) Target outfit style direction/aesthetic
 * @param selectedVibes - (OPTIONAL) Style vibes (e.g. "Streetwear", "Clean", "Old Money")
 * @param contextTags - (OPTIONAL) Context tags (e.g. occasion, season)
 * @returns Object with imageBase64 and remainingCredits
 */
export const generateFromDescription = onCall(functionOptions, async (request) => {
  // Require authentication
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in to generate outfits');
  }

  const uid = request.auth.uid;
  const { selfieBase64, userDescription, targetColor, selectedVibes, contextTags, aspectRatio } = request.data as {
    selfieBase64?: string;
    userDescription?: string;
    targetColor?: string;
    selectedVibes?: string;
    contextTags?: string;
    aspectRatio?: number;
  };

  // Validate inputs BEFORE rate limiting (fast fail)
  // Note: targetColor (Style Direction) is now optional
  if (!selfieBase64 || !userDescription) {
    throw new HttpsError('invalid-argument', 'Missing required data: selfieBase64 and userDescription');
  }

  // Validate base64 string size
  const maxImageSize = 10 * 1024 * 1024; // 10MB
  if (selfieBase64.length > maxImageSize) {
    throw new HttpsError('invalid-argument', 'Image size exceeds maximum allowed (10MB)');
  }

  // Validate description lengths
  if (userDescription.length > 1000) {
    throw new HttpsError('invalid-argument', 'Description too long (max 1000 characters)');
  }
  // Only validate targetColor length if it's provided
  if (targetColor && targetColor.length > 500) {
    throw new HttpsError('invalid-argument', 'Style direction too long (max 500 characters)');
  }

  // Map aspect ratio to supported value (default to 3:4 portrait if not provided)
  const aspectRatioStr = aspectRatio
    ? mapToSupportedAspectRatio(aspectRatio)
    : "3:4";

  // Execute with rate limiting and credit protection
  // Credits are ONLY consumed if generation succeeds
  return executeWithRateLimiting(uid, 1, async () => {
    // Google Native Format payload
    const payload = {
      contents: [{
        parts: [
          { text: buildDescribePrompt(userDescription, targetColor || '', selectedVibes || '', contextTags || '') },
          {
            inline_data: {
              mime_type: 'image/jpeg',
              data: selfieBase64
            }
          }
        ]
      }],
      generationConfig: {
        responseModalities: ["IMAGE"],
        imageConfig: {
          aspectRatio: aspectRatioStr,
          imageSize: "2K"  // Higher quality than default 1K
        }
      }
    };

    const response = await fetch(API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${laozhangApiKey.value().trim()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('API error:', response.status, errorText);
      throw new HttpsError('internal', `API request failed: ${response.status}`);
    }

    const result = await response.json() as ApiResponse;

    // Extract image from Google Native Format response
    const imageData = result.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;

    if (!imageData) {
      console.error('Could not extract image from response:', JSON.stringify(result).substring(0, 500));
      throw new HttpsError('internal', 'Could not extract image from API response');
    }

    return { imageBase64: imageData };
  });
});

// ============================================================
// FREE ONBOARDING GENERATION (NO CREDIT CONSUMPTION)
// ============================================================

/**
 * Generate outfit from text description during onboarding - FREE (no credit consumption)
 *
 * This function is specifically for the onboarding flow and does NOT consume credits.
 * Each user can only use this function ONCE (tracked via usedFreeOnboardingGeneration flag).
 *
 * After using this, users still have their full 2 free credits to use post-onboarding.
 *
 * SECURITY:
 * - Requires Firebase Auth
 * - Can only be used once per user (checked atomically via Firestore transaction)
 * - No rate limiting on this single-use function
 *
 * @param selfieBase64 - Base64 encoded selfie image
 * @param userDescription - Text description of desired outfit
 * @param targetColor - (OPTIONAL) Target outfit style direction/aesthetic
 * @param selectedVibes - (OPTIONAL) Style vibes
 * @param contextTags - (OPTIONAL) Context tags
 * @returns Object with imageBase64 (no credit deduction)
 */
export const generateOnboardingOutfit = onCall(functionOptions, async (request) => {
  // Require authentication
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in to generate outfits');
  }

  const uid = request.auth.uid;
  const { selfieBase64, userDescription, targetColor, selectedVibes, contextTags, aspectRatio } = request.data as {
    selfieBase64?: string;
    userDescription?: string;
    targetColor?: string;
    selectedVibes?: string;
    contextTags?: string;
    aspectRatio?: number;
  };

  // Validate inputs BEFORE checking onboarding status (fast fail)
  // Note: targetColor (Style Direction) is now optional
  if (!selfieBase64 || !userDescription) {
    throw new HttpsError('invalid-argument', 'Missing required data: selfieBase64 and userDescription');
  }

  // Validate base64 string size
  const maxImageSize = 10 * 1024 * 1024; // 10MB
  if (selfieBase64.length > maxImageSize) {
    throw new HttpsError('invalid-argument', 'Image size exceeds maximum allowed (10MB)');
  }

  // Validate description lengths
  if (userDescription.length > 1000) {
    throw new HttpsError('invalid-argument', 'Description too long (max 1000 characters)');
  }
  // Only validate targetColor length if it's provided
  if (targetColor && targetColor.length > 500) {
    throw new HttpsError('invalid-argument', 'Style direction too long (max 500 characters)');
  }

  // Import admin SDK for Firestore access
  const admin = await import('firebase-admin');
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  const db = admin.firestore();
  const userRef = db.collection('users').doc(uid);

  // Check and mark free onboarding generation atomically
  let alreadyUsed = false;
  await db.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    if (!userDoc.exists) {
      throw new HttpsError('not-found', 'User profile not found');
    }

    const userData = userDoc.data();
    if (userData?.usedFreeOnboardingGeneration === true) {
      alreadyUsed = true;
      return;
    }

    // Mark as used BEFORE generation starts
    transaction.update(userRef, {
      usedFreeOnboardingGeneration: true,
    });
  });

  if (alreadyUsed) {
    // User already used their free generation - fall back to normal flow with credits
    throw new HttpsError(
      'failed-precondition',
      'Free onboarding generation already used. Please use regular generation.'
    );
  }

  console.log(`User ${uid} using FREE onboarding generation (no credits consumed)`);

  // Map aspect ratio to supported value (default to 3:4 portrait if not provided)
  const aspectRatioStr = aspectRatio
    ? mapToSupportedAspectRatio(aspectRatio)
    : "3:4";

  // Perform the actual generation (no credit consumption) - Google Native Format
  const payload = {
    contents: [{
      parts: [
        { text: buildDescribePrompt(userDescription, targetColor || '', selectedVibes || '', contextTags || '') },
        {
          inline_data: {
            mime_type: 'image/jpeg',
            data: selfieBase64
          }
        }
      ]
    }],
    generationConfig: {
      responseModalities: ["IMAGE"],
      imageConfig: {
        aspectRatio: aspectRatioStr,
        imageSize: "2K"  // Higher quality than default 1K
      }
    }
  };

  const response = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${laozhangApiKey.value().trim()}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error('API error:', response.status, errorText);
    throw new HttpsError('internal', `API request failed: ${response.status}`);
  }

  const result = await response.json() as ApiResponse;

  // Extract image from Google Native Format response
  const imageData = result.candidates?.[0]?.content?.parts?.[0]?.inlineData?.data;

  if (!imageData) {
    console.error('Could not extract image from response:', JSON.stringify(result).substring(0, 500));
    throw new HttpsError('internal', 'Could not extract image from API response');
  }

  console.log(`User ${uid} successfully completed FREE onboarding generation`);

  return { imageBase64: imageData, freeGeneration: true };
});
