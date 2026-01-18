# Firebase Migration Guide for HairAI API Keys

This document describes how to migrate the hardcoded laozhang.ai API key from the Flutter app to secure Firebase Cloud Functions.

## Current Implementation (Development)

Currently, the API key is hardcoded in `lib/services/hairstyle_service.dart`:

```dart
// In LaozhangHairstyleService and LaozhangHairColorService
static const String _apiKey = 'sk-xxxx...';
static const String _apiUrl = 'https://api.laozhang.ai/v1/chat/completions';
```

**This is NOT secure for production.** Follow this guide to migrate to Firebase.

---

## Migration Steps

### Step 1: Set Up Firebase Project

1. Create a Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Add your Flutter app to the project
3. Download and add `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
4. Install Firebase CLI: `npm install -g firebase-tools`
5. Initialize Firebase in your project: `firebase init functions`

### Step 2: Create Firebase Cloud Function

Create `functions/index.js`:

```javascript
const functions = require('firebase-functions');
const fetch = require('node-fetch');

// Store API key in Firebase environment config
// Run: firebase functions:config:set laozhang.apikey="sk-your-api-key-here"

const API_KEY = functions.config().laozhang.apikey;
const API_URL = 'https://api.laozhang.ai/v1/chat/completions';
const MODEL = 'gemini-2.5-flash-image-preview';

// Hairstyle transplant prompt
const HAIRSTYLE_PROMPT = `
[Your full hairstyle transplant prompt here - copy from hairstyle_service.dart]
`;

// Hair color change prompt builder
function buildColorChangePrompt(targetColor) {
  return `
You are performing a strictly localized color transformation...
[Your full color change prompt here]
Change ONLY the hair color to: ${targetColor}.
...
`;
}

/**
 * Generate hairstyle - transplants reference hairstyle onto selfie
 */
exports.generateHairstyle = functions
  .runWith({ timeoutSeconds: 300, memory: '1GB' })
  .https.onCall(async (data, context) => {
    // Optional: Check authentication
    // if (!context.auth) {
    //   throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    // }

    const { selfieBase64, referenceBase64 } = data;

    if (!selfieBase64 || !referenceBase64) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required images');
    }

    const payload = {
      model: MODEL,
      stream: false,
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: HAIRSTYLE_PROMPT },
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${selfieBase64}` } },
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${referenceBase64}` } },
        ]
      }]
    };

    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        const error = await response.text();
        throw new functions.https.HttpsError('internal', `API error: ${error}`);
      }

      const result = await response.json();
      const content = result.choices[0]?.message?.content;

      // Extract base64 image from response
      const imageData = extractImageFromContent(content);

      return { imageBase64: imageData };
    } catch (error) {
      console.error('Error:', error);
      throw new functions.https.HttpsError('internal', error.message);
    }
  });

/**
 * Change hair color - applies target color to selfie
 */
exports.changeHairColor = functions
  .runWith({ timeoutSeconds: 300, memory: '1GB' })
  .https.onCall(async (data, context) => {
    const { selfieBase64, targetColorDescription } = data;

    if (!selfieBase64 || !targetColorDescription) {
      throw new functions.https.HttpsError('invalid-argument', 'Missing required data');
    }

    const payload = {
      model: MODEL,
      stream: false,
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: buildColorChangePrompt(targetColorDescription) },
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${selfieBase64}` } },
        ]
      }]
    };

    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        const error = await response.text();
        throw new functions.https.HttpsError('internal', `API error: ${error}`);
      }

      const result = await response.json();
      const content = result.choices[0]?.message?.content;
      const imageData = extractImageFromContent(content);

      return { imageBase64: imageData };
    } catch (error) {
      console.error('Error:', error);
      throw new functions.https.HttpsError('internal', error.message);
    }
  });

/**
 * Extract base64 image from API response content
 */
function extractImageFromContent(content) {
  if (typeof content !== 'string') {
    throw new Error('Unexpected response format');
  }

  // Check for markdown image format
  const markdownMatch = content.match(/!\[.*?\]\(data:image\/[^;]+;base64,([A-Za-z0-9+/=]+)\)/);
  if (markdownMatch) {
    return markdownMatch[1];
  }

  // Check for data URI format
  const dataUriMatch = content.match(/data:image\/[^;]+;base64,([A-Za-z0-9+/=]+)/);
  if (dataUriMatch) {
    return dataUriMatch[1];
  }

  throw new Error('Could not extract image from response');
}
```

### Step 3: Set API Key in Firebase Config

```bash
firebase functions:config:set laozhang.apikey="sk-ebOXFUfPhGaRuF0O8aF56252Fc974aDa9c4121Fd9a8a91C1"
```

### Step 4: Deploy Functions

```bash
firebase deploy --only functions
```

### Step 5: Update Flutter Service

Update `lib/services/hairstyle_service.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';

/// Secure implementation using Firebase Cloud Functions
class FirebaseHairstyleService implements HairstyleService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  Future<Uint8List> generateHairstyle({
    required Uint8List selfieImage,
    required Uint8List referenceImage,
  }) async {
    final callable = _functions.httpsCallable(
      'generateHairstyle',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );

    final result = await callable.call({
      'selfieBase64': base64Encode(selfieImage),
      'referenceBase64': base64Encode(referenceImage),
    });

    final imageBase64 = result.data['imageBase64'] as String;
    return base64Decode(imageBase64);
  }
}

/// Secure implementation for hair color change
class FirebaseHairColorService implements HairColorService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  Future<Uint8List> changeHairColor({
    required Uint8List selfieImage,
    required String targetColorDescription,
  }) async {
    final callable = _functions.httpsCallable(
      'changeHairColor',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );

    final result = await callable.call({
      'selfieBase64': base64Encode(selfieImage),
      'targetColorDescription': targetColorDescription,
    });

    final imageBase64 = result.data['imageBase64'] as String;
    return base64Decode(imageBase64);
  }
}
```

### Step 6: Update Screen Files

In `lib/screens/hair_try_on_screen.dart`:
```dart
// Change from:
final HairstyleService _hairstyleService = LaozhangHairstyleService();

// To:
final HairstyleService _hairstyleService = FirebaseHairstyleService();
```

In `lib/screens/color_change_screen.dart`:
```dart
// Change from:
final HairColorService _colorService = LaozhangHairColorService();

// To:
final HairColorService _colorService = FirebaseHairColorService();
```

### Step 7: Add Firebase Dependencies

Update `pubspec.yaml`:
```yaml
dependencies:
  firebase_core: ^2.24.0
  cloud_functions: ^4.5.0
```

---

## Security Best Practices

1. **Never commit API keys** - The current hardcoded key should be removed before pushing to public repos
2. **Use Firebase Authentication** - Uncomment the auth check in Cloud Functions to require user login
3. **Set up billing alerts** - Monitor API usage costs in both Firebase and laozhang.ai
4. **Rate limiting** - Add rate limiting in Cloud Functions to prevent abuse
5. **Input validation** - Validate image sizes and formats before sending to API

---

## Files to Update During Migration

| File | Change Required |
|------|-----------------|
| `pubspec.yaml` | Add firebase_core, cloud_functions |
| `lib/services/hairstyle_service.dart` | Add Firebase implementations, remove API key |
| `lib/screens/hair_try_on_screen.dart` | Switch to FirebaseHairstyleService |
| `lib/screens/color_change_screen.dart` | Switch to FirebaseHairColorService |
| `android/app/google-services.json` | Add Firebase config |
| `ios/Runner/GoogleService-Info.plist` | Add Firebase config |
| `functions/index.js` | Create new file with Cloud Functions |

---

## Estimated Migration Time

- Firebase setup: 15-30 minutes
- Cloud Functions implementation: 30-45 minutes
- Flutter integration: 15-20 minutes
- Testing: 30-60 minutes

**Total: 1.5 - 2.5 hours**

---

## Cost Considerations

| Service | Cost |
|---------|------|
| laozhang.ai API | ~$0.025 per image generation |
| Firebase Functions | Free tier: 2M invocations/month |
| Firebase Functions | Paid: $0.40 per million invocations |

For a typical user generating 10 images/day:
- API cost: ~$7.50/month per active user
- Firebase: Negligible unless at scale

---

*Last Updated: 2025-12-25*
