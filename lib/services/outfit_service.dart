import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import 'credit_service.dart';

// ============================================================================
// RATE LIMIT EXCEPTIONS
// ============================================================================

/// Exception thrown when user is rate limited (cooldown period)
class RateLimitCooldownException implements Exception {
  final int retryAfterSeconds;
  final String message;

  RateLimitCooldownException({
    required this.retryAfterSeconds,
    this.message = 'Please wait a moment before generating again',
  });

  @override
  String toString() => 'RateLimitCooldownException: $message (retry after ${retryAfterSeconds}s)';
}

/// Exception thrown when user has too many concurrent generations
class ConcurrentLimitException implements Exception {
  final String message;

  ConcurrentLimitException({
    this.message = 'Too many requests in progress',
  });

  @override
  String toString() => 'ConcurrentLimitException: $message';
}

/// Abstract service interface for hairstyle generation
abstract class OutfitService {
  Future<Uint8List> generateOutfit({
    required Uint8List selfieImage,
    required Uint8List referenceImage,
  });
}

/// Legacy implementation using laozhang.ai API directly
/// WARNING: For development/testing only - DO NOT use in production!
/// Use FirebaseOutfitService for production (API key stored in Secret Manager)
@Deprecated('Use FirebaseOutfitService for production')
class LaozhangOutfitService implements OutfitService {
  // API key removed for security - use Firebase Cloud Functions instead
  static const String _apiKey = '';
  static const String _apiUrl = 'https://api.laozhang.ai/v1/chat/completions';
  static const String _model = 'gemini-3-pro-image-preview';

  static const String _hairstylePrompt = '''
TASK: PHOTOREALISTIC OUTFIT TRY-ON

INPUT A (user.jpg): Base identity, body, pose, framing, and environment.
INPUT B (reference.jpg): Clothing / outfit and accessories source ONLY.

SYSTEM INSTRUCTIONS:
You are an expert photographic retoucher and fashion compositing specialist. 
Your goal is to replace ONLY the clothing and accessories worn by the subject in INPUT A with the outfit from INPUT B, while preserving 100% of the subject’s identity, body, pose, and environment.

––––––––––––––––––––––––––––––
1. IDENTITY & BODY PRESERVATION (PIXEL-LOCK)
––––––––––––––––––––––––––––––
- Keep the subject’s face, body shape, proportions, skin tone, and physical identity EXACTLY as they appear in INPUT A.
- Maintain all natural details including skin texture, shadows, muscle definition, body curves, and imperfections.
- Do NOT alter facial features, body size, posture, or pose.
- Do NOT apply beautification, slimming, reshaping, or body enhancement of any kind.

––––––––––––––––––––––––––––––
2. COMPOSITION & FRAMING LOCK
––––––––––––––––––––––––––––––
- Preserve the exact camera angle, zoom level, perspective, and crop of INPUT A.
- NO CROPPING. NO REPOSITIONING. NO BACKGROUND CHANGES.
- The subject must remain in the exact same position within the frame.
- Hands, arms, legs, and body orientation must remain unchanged.

––––––––––––––––––––––––––––––
3. CLOTHING & ACCESSORY EXTRACTION (REFERENCE IMAGE)
––––––––––––––––––––––––––––––
- Extract ONLY the clothing and accessories from INPUT B.
- This includes garments AND any worn or carried accessories such as shoes, scarf, hat, handbag, belt, jewelry, or eyewear.
- Capture accurate garment cut, fit, layering, fabric texture, stitching, seams, folds, materials, and color.
- Ignore the reference model’s body, face, pose, background, and lighting.
- Do NOT copy the reference person’s body proportions, posture, or anatomy.

––––––––––––––––––––––––––––––
4. OUTFIT & ACCESSORY APPLICATION
––––––––––––––––––––––––––––––
- Replace the subject’s existing clothing and accessories in INPUT A with the extracted outfit and accessories from INPUT B.
- Fit all garments naturally to the subject’s body shape and pose.
- Accessories must be placed realistically and proportionally (e.g., shoes aligned to feet, bags positioned naturally on shoulder or hand, scarves wrapped naturally, hats aligned correctly on the head).
- Clothing and accessories must drape and interact realistically with correct gravity, fabric tension, folds, creases, and overlap.
- Ensure sleeves, waistlines, hems, collars, pant legs, and footwear align correctly with the subject’s anatomy.
- Preserve any visible skin, hands, neck, legs, and feet exactly as they appear in INPUT A unless covered by the new outfit or accessories.

––––––––––––––––––––––––––––––
5. LIGHTING, SHADOWS & REALISM
––––––––––––––––––––––––––––––
- Match the lighting direction, intensity, and color temperature of INPUT A — NOT the reference image.
- Apply realistic shadows and contact points where clothing and accessories touch the body (under arms, waist, neck, feet, straps, folds, and layers).
- Maintain a natural "shot on mobile phone" realism.
- Avoid studio lighting, HDR effects, fashion editorial styling, or artificial glow unless present in INPUT A.

––––––––––––––––––––––––––––––
6. STRICT RESTRICTIONS
––––––––––––––––––––––––––––––
- Do NOT change the subject’s face, hair, skin, body, pose, or background.
- Do NOT add any clothing or accessories that do NOT exist in the reference image.
- Do NOT stylize, editorialize, exaggerate, or idealize the outfit.
- Do NOT modify image quality or apply filters.

––––––––––––––––––––––––––––––
FINAL REQUIREMENT:
The final image must look like a real, unedited photo of the same person from INPUT A wearing the clothing and accessories from INPUT B, taken at the same moment, in the same place, with the same camera.

''';

  @override
  Future<Uint8List> generateOutfit({
    required Uint8List selfieImage,
    required Uint8List referenceImage,
  }) async {
    // Convert images to base64
    final selfieBase64 = base64Encode(selfieImage);
    final referenceBase64 = base64Encode(referenceImage);

    // Build the request payload
    final payload = {
      'model': _model,
      'stream': false,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _hairstylePrompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$selfieBase64'}
            },
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$referenceBase64'}
            },
          ]
        }
      ]
    };

    // Make the API call
    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw OutfitGenerationException(
        'API request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    // Parse the response
    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;

    // Debug: Log the response structure
    print('=== HAIRSTYLE API RESPONSE DEBUG ===');
    print('Response keys: ${responseJson.keys.toList()}');

    // Extract the image from the response
    final choices = responseJson['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw OutfitGenerationException('No choices in API response');
    }

    final message = choices[0]['message'] as Map<String, dynamic>?;
    if (message == null) {
      throw OutfitGenerationException('No message in API response');
    }

    final content = message['content'];

    // Debug: Log content type and structure
    print('Content type: ${content.runtimeType}');
    if (content is String) {
      print('Content string length: ${content.length}');
      print('Content preview: ${content.substring(0, content.length > 200 ? 200 : content.length)}...');
    } else if (content is List) {
      print('Content is List with ${content.length} items');
      for (int i = 0; i < content.length; i++) {
        final item = content[i];
        if (item is Map) {
          print('  Item $i type: ${item['type']}');
          if (item['type'] == 'text') {
            final text = item['text'] as String? ?? '';
            print('  Item $i text preview: ${text.substring(0, text.length > 100 ? 100 : text.length)}...');
          }
        }
      }
    }
    print('=== END DEBUG ===');

    // Handle different response formats
    Uint8List? resultImage;

    if (content is String) {
      // Try to extract base64 image from string response
      resultImage = ImageExtractionUtils.extractImageFromContent(content);
    } else if (content is List) {
      // Content might be a list with image parts
      // Collect ALL images found - the last one is typically the generated result
      // (input images may be echoed back first)
      final List<Uint8List> foundImages = [];

      for (final part in content) {
        if (part is Map<String, dynamic>) {
          Uint8List? extractedImage;

          if (part['type'] == 'image' && part['image'] != null) {
            extractedImage = ImageExtractionUtils.decodeBase64Image(part['image'] as String);
          } else if (part['type'] == 'image_url') {
            final imageUrl = part['image_url'];
            if (imageUrl is Map && imageUrl['url'] != null) {
              extractedImage = ImageExtractionUtils.extractImageFromUrl(imageUrl['url'] as String);
            }
          } else if (part['type'] == 'inline_data' && part['data'] != null) {
            // Handle Gemini's inline_data format
            extractedImage = ImageExtractionUtils.decodeBase64Image(part['data'] as String);
          }

          if (extractedImage != null) {
            foundImages.add(extractedImage);
            print('Found image ${foundImages.length}: ${extractedImage.length} bytes');
          }
        }
      }

      // Use the LAST image found (most likely the generated result, not echoed inputs)
      if (foundImages.isNotEmpty) {
        print('Total images found: ${foundImages.length}. Using last one.');
        resultImage = foundImages.last;
      }
    } else if (content is Map<String, dynamic>) {
      // Content might be a map with image data
      if (content['image'] != null) {
        resultImage = ImageExtractionUtils.decodeBase64Image(content['image'] as String);
      }
    }

    if (resultImage == null) {
      // More detailed error with full response structure
      final responsePreview = response.body.length > 1000
          ? response.body.substring(0, 1000)
          : response.body;
      throw OutfitGenerationException(
        'Could not extract image from API response. Content type: ${content.runtimeType}. Response: $responsePreview...',
      );
    }

    return resultImage;
  }
}

// ============================================================================
// SHARED IMAGE EXTRACTION UTILITIES
// ============================================================================

/// Utility class for extracting images from API responses
class ImageExtractionUtils {
  /// Extract base64 image from API response content
  static Uint8List? extractImageFromContent(String content) {
    // Method 1: Find data URI and extract everything after "base64,"
    const base64Marker = 'base64,';
    final markerIndex = content.indexOf(base64Marker);
    if (markerIndex != -1) {
      // Extract from after the marker to the end or closing delimiter
      String remaining = content.substring(markerIndex + base64Marker.length);

      // Find the end of the base64 data
      int endIndex = remaining.length;
      for (final delimiter in [')', ']', '"', "'", '\n', ' ']) {
        final idx = remaining.indexOf(delimiter);
        if (idx != -1 && idx < endIndex) {
          endIndex = idx;
        }
      }

      final base64Data = remaining.substring(0, endIndex);
      final result = decodeBase64Image(base64Data);
      if (result != null) {
        return result;
      }
    }

    // Method 2: Check for markdown image format
    final markdownMatch = RegExp(r'!\[.*?\]\(\s*(data:image/[^;]+;base64,([A-Za-z0-9+/=\s]+))\s*\)').firstMatch(content);
    if (markdownMatch != null) {
      return decodeBase64Image(markdownMatch.group(2)!);
    }

    // Method 3: Check for data URI format
    final dataUriMatch = RegExp(r'data:image/[^;]+;base64,([A-Za-z0-9+/=\s]+)').firstMatch(content);
    if (dataUriMatch != null) {
      return decodeBase64Image(dataUriMatch.group(1)!);
    }

    // Method 4: Direct base64 string
    if (content.length > 100 && !content.contains(' ') && !content.contains('\n')) {
      return decodeBase64Image(content);
    }

    return null;
  }

  /// Extract image from URL/data URI
  static Uint8List? extractImageFromUrl(String url) {
    if (url.startsWith('data:image')) {
      final base64Part = url.split('base64,');
      if (base64Part.length == 2) {
        return decodeBase64Image(base64Part[1]);
      }
    }
    return null;
  }

  /// Decode base64 string to image bytes
  static Uint8List? decodeBase64Image(String base64String) {
    try {
      String cleaned = base64String.trim();
      // Remove data URI prefix if present
      if (cleaned.contains('base64,')) {
        cleaned = cleaned.split('base64,')[1];
      }
      // Remove whitespace/newlines
      cleaned = cleaned.replaceAll(RegExp(r'\s'), '');
      return base64Decode(cleaned);
    } catch (e) {
      return null;
    }
  }
}

/// Exception thrown when hairstyle generation fails
class OutfitGenerationException implements Exception {
  final String message;
  OutfitGenerationException(this.message);

  @override
  String toString() => 'OutfitGenerationException: $message';
}

// ============================================================================
// PHOTOREALISTIC OUTFIT COMPOSITION USING USER-SUPPLIED GARMENT IMAGES
// ============================================================================

/// Abstract service interface for AI try-on with multiple clothing items
abstract class OutfitStyleService {
  Future<Uint8List> changeOutfitStyle({
    required Uint8List selfieImage,
    required List<Uint8List> clothingItems,
  });
}

/// Legacy implementation using laozhang.ai API directly for hair color
/// WARNING: For development/testing only - DO NOT use in production!
/// Use FirebaseOutfitStyleService for production (API key stored in Secret Manager)
@Deprecated('Use FirebaseOutfitStyleService for production')
class LaozhangOutfitStyleService implements OutfitStyleService {
  // API key removed for security - use Firebase Cloud Functions instead
  static const String _apiKey = '';
  static const String _apiUrl = 'https://api.laozhang.ai/v1/chat/completions';
  static const String _model = 'gemini-3-pro-image-preview';

  static String _buildColorChangePrompt(String targetColor) => '''
TASK: PHOTOREALISTIC OUTFIT COMPOSITION USING USER-SUPPLIED GARMENT IMAGES
INPUTS:

INPUT A (user.jpg – REQUIRED)
The base image containing the subject’s identity, body, pose, framing, lighting, and environment.

INPUT B–F (OPTIONAL, UP TO 5 IMAGES TOTAL)
User-supplied clothing item images or reference images.
These may include:

Individual garments (e.g. jeans, t-shirt, jacket, hat, sunglasses)

Accessories

Footwear

OR full-outfit reference images

Not all slots will be filled. Treat missing inputs gracefully.

SYSTEM ROLE:

You are an expert fashion stylist and photorealistic image compositor specializing in virtual try-on.
Your goal is to dress the subject in INPUT A using the uploaded garment/reference images when provided, while preserving 100% identity, pose, and photographic realism.

1. ABSOLUTE IDENTITY, BODY & SCENE LOCK

(Same as your existing rules — unchanged)

INPUT A is immutable.

Preserve face, body shape, proportions, pose, skin tone, hair, and background EXACTLY.

No reshaping, beautifying, smoothing, or enhancements.

No camera, crop, or background changes.

2. IMAGE ROLE CLASSIFICATION (CRITICAL STEP)

Before styling, analyze each optional image (INPUT B–F) and classify it into ONE of the following roles:

A. SINGLE GARMENT ITEM

Examples:

Jeans

T-shirt

Jacket

Hoodie

Dress

Hat

Sunglasses

Shoes

B. ACCESSORY

Examples:

Bag

Belt

Jewelry

Watch

Scarf

C. FULL OUTFIT REFERENCE

Examples:

A model wearing a complete styled look

Editorial or mirror selfie outfit

Street-style reference

D. AMBIGUOUS / POOR INPUT

Examples:

Flat lay with multiple items

Cropped or unclear garment

Non-fashion image

You MUST determine the most reasonable role for each image.

3. GARMENT PRIORITY & CONFLICT RULES

When multiple images are provided:

SINGLE GARMENT IMAGES take priority over FULL OUTFIT references

If multiple SINGLE GARMENTS overlap the same category:

Use the clearest, most wearable image

Ignore duplicates gracefully

FULL OUTFIT references are used as:

Styling guidance (fit, proportions, layering, vibe)

NOT as a literal copy unless no single garments are provided

AMBIGUOUS inputs:

Use only if they clearly improve coherence

Otherwise ignore silently

4. OUTFIT CONSTRUCTION LOGIC

Build the final outfit using this hierarchy:

CASE 1: Multiple Single Garments Provided

Combine them into one coherent outfit

Preserve:

Color

Fabric type

Cut and silhouette

Adjust fit realistically to the subject’s body and pose

Ensure natural layering and proportions

CASE 2: Mix of Single Garments + Full Outfit Reference

Use SINGLE GARMENTS as fixed anchors

Use FULL OUTFIT image for:

Styling direction

Layering inspiration

Overall vibe

Do NOT override provided garments to match the reference

CASE 3: Only Full Outfit Reference(s) Provided

Recreate a realistic interpretation of the outfit on the subject

Match:

Overall style

Color harmony

Formality level

Do NOT copy branding, logos, or exact textures unless clearly visible

CASE 4: Only INPUT A Provided

Fall back to STYLE BRIEF + VIBES prompt logic

Generate a complete outfit naturally

5. FIT, DRAPE & REALISM REQUIREMENTS

Clothing must respect:

Gravity

Fabric tension

Body contact points

Natural folds and wrinkles

Ensure correct interaction with:

Arms, hands, legs, waist, shoulders

Sunglasses, hats, and accessories must align perfectly with head and face orientation.

6. LIGHTING & PHOTOGRAPHIC INTEGRATION

Match lighting direction, softness, color temperature, and shadow intensity from INPUT A.

Apply realistic contact shadows between clothing and body.

Maintain a casual, real-world mobile-photo aesthetic.

7. STRICT PROHIBITIONS

No face or body alteration

No editorial or stylized fashion effects

No background changes

No filters, glow, or AI “beautification”

No changing the subject’s gender expression or identity

FINAL REQUIREMENT

The final image must look like a real photo of the same person, taken in the same moment and location, wearing a cohesive outfit constructed from the uploaded images where provided.

OUTPUT:

Return ONLY the final transformed image.
''';

  @override
  Future<Uint8List> changeOutfitStyle({
    required Uint8List selfieImage,
    required List<Uint8List> clothingItems,
  }) async {
    // Convert user image to base64
    final selfieBase64 = base64Encode(selfieImage);

    // Build content array starting with prompt and user image
    final List<Map<String, dynamic>> messageContent = [
      {'type': 'text', 'text': _buildColorChangePrompt('')},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$selfieBase64'}
      },
    ];

    // Add clothing item images (up to 5 additional images)
    for (final clothingItem in clothingItems) {
      messageContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(clothingItem)}'}
      });
    }

    // Build the request payload
    final payload = {
      'model': _model,
      'stream': false,
      'messages': [
        {
          'role': 'user',
          'content': messageContent,
        }
      ]
    };

    // Make the API call
    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw OutfitStyleChangeException(
        'API request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    // Parse the response
    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;

    // Extract the image from the response
    final choices = responseJson['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw OutfitStyleChangeException('No choices in API response');
    }

    final message = choices[0]['message'] as Map<String, dynamic>?;
    if (message == null) {
      throw OutfitStyleChangeException('No message in API response');
    }

    final content = message['content'];

    // Handle different response formats using shared utility
    Uint8List? resultImage;

    if (content is String) {
      resultImage = ImageExtractionUtils.extractImageFromContent(content);
    } else if (content is List) {
      for (final part in content) {
        if (part is Map<String, dynamic>) {
          if (part['type'] == 'image' && part['image'] != null) {
            resultImage = ImageExtractionUtils.decodeBase64Image(part['image'] as String);
            break;
          } else if (part['type'] == 'image_url') {
            final imageUrl = part['image_url'];
            if (imageUrl is Map && imageUrl['url'] != null) {
              resultImage = ImageExtractionUtils.extractImageFromUrl(imageUrl['url'] as String);
              break;
            }
          }
        }
      }
    } else if (content is Map<String, dynamic>) {
      if (content['image'] != null) {
        resultImage = ImageExtractionUtils.decodeBase64Image(content['image'] as String);
      }
    }

    if (resultImage == null) {
      throw OutfitStyleChangeException(
        'Could not extract image from API response. Response: ${response.body.substring(0, 500)}...',
      );
    }

    return resultImage;
  }
}

/// Exception thrown when hair color change fails
class OutfitStyleChangeException implements Exception {
  final String message;
  OutfitStyleChangeException(this.message);

  @override
  String toString() => 'OutfitStyleChangeException: $message';
}

// ============================================================================
// TEXT-DESCRIBED HAIRSTYLE SERVICE
// ============================================================================

/// Abstract service interface for text-described hairstyle generation
abstract class DescribeOutfitService {
  Future<Uint8List> generateFromDescription({
    required Uint8List selfieImage,
    required String userDescription,
    required String targetColor,
    String selectedVibes = '',
    String contextTags = '',
  });
}

/// Legacy implementation using laozhang.ai API directly for text-described hairstyle
/// WARNING: For development/testing only - DO NOT use in production!
/// Use FirebaseDescribeOutfitService for production (API key stored in Secret Manager)
@Deprecated('Use FirebaseDescribeOutfitService for production')
class LaozhangDescribeOutfitService implements DescribeOutfitService {
  // API key removed for security - use Firebase Cloud Functions instead
  static const String _apiKey = '';
  static const String _apiUrl = 'https://api.laozhang.ai/v1/chat/completions';
  static const String _model = 'gemini-3-pro-image-preview';

  static String _buildDescribePrompt(
    String userDescription,
    String targetColor,
    String selectedVibes,
    String contextTags,
  ) => '''
TASK: PHOTOREALISTIC OUTFIT STYLING BASED ON USER INTENT

INPUTS:
- INPUT A (user.jpg): Base identity, body, pose, framing, lighting, and environment.
- STYLE BRIEF (TEXT): "$userDescription"
- SELECTED VIBES (OPTIONAL): "$selectedVibes"
- CONTEXT TAGS (OPTIONAL): "$contextTags"
  (e.g. occasion, season, weather, footwear preference)

SYSTEM ROLE:
You are an expert photographic retoucher and fashion styling specialist.
Your goal is to replace ONLY the outfit worn by the subject in INPUT A with a realistic, wearable outfit that fulfills the user’s intent, while preserving 100% of the subject’s identity, body, pose, and photographic integrity.

––––––––––––––––––––––––––––––
1. ABSOLUTE IDENTITY & BODY LOCK
––––––––––––––––––––––––––––––
- INPUT A is the immutable base image.
- Preserve the subject’s face, body shape, proportions, skin tone, and physical identity EXACTLY.
- Maintain all natural details including skin texture, shadows, muscle definition, body curves, and imperfections.
- Do NOT alter facial features, body size, posture, or pose.
- Do NOT apply beautification, reshaping, smoothing, or enhancement of any kind.

––––––––––––––––––––––––––––––
2. COMPOSITION & FRAMING LOCK
––––––––––––––––––––––––––––––
- Preserve the exact camera angle, zoom level, perspective, crop, and background of INPUT A.
- NO CROPPING, NO REPOSITIONING, NO BACKGROUND CHANGES.
- The subject must remain in the exact same position within the frame.

––––––––––––––––––––––––––––––
3. STYLE INTENT INTERPRETATION (PRIMARY DRIVER)
––––––––––––––––––––––––––––––
- Treat the STYLE BRIEF as the primary source of truth.
- Interpret the brief as a real-world styling request, not an abstract fashion prompt.
- Resolve ambiguity conservatively and naturally.
- Prioritize wearability, coherence, and appropriateness over trend exaggeration.
- If multiple interpretations are possible, choose the most realistic and versatile option.

––––––––––––––––––––––––––––––
4. OUTFIT CONSTRAINT HANDLING (USER-LED)
––––––––––––––––––––––––––––––
- If the STYLE BRIEF mentions specific items to keep, include, or anchor
  (e.g. “blue jeans”, “white sneakers”, “black blazer”):
  - Treat those items as FIXED ANCHORS.
  - Preserve their implied style, formality, and color intent.
  - Build the rest of the outfit to complement these anchors naturally.
- Never override or contradict explicitly mentioned clothing preferences.
- If the user expresses uncertainty (“not sure what top to wear”), resolve it cohesively and conservatively.

––––––––––––––––––––––––––––––
5. VIBE & CONTEXT REFINEMENT (SECONDARY)
––––––––––––––––––––––––––––––
- Use SELECTED VIBES as subtle stylistic guidance only.
- Vibes may influence:
  - Silhouette
  - Color palette
  - Level of polish vs casualness
- Vibes must NEVER override the STYLE BRIEF or fixed anchors.
- If no vibes are selected, rely entirely on the STYLE BRIEF.
- Interpret vibes in a gender-appropriate way based on the subject’s appearance without altering identity.

––––––––––––––––––––––––––––––
6. CLOTHING & ACCESSORY EXECUTION
––––––––––––––––––––––––––––––
- Replace the subject’s existing outfit with the newly styled clothing.
- Outfit may naturally include:
  - Shoes
  - Outerwear
  - Bag or handbag
  - Belt, scarf, or hat
- Do NOT add accessories unless they are appropriate and contextually justified.
- Fit all clothing realistically to the subject’s body and pose.
- Ensure correct drape, fabric tension, gravity, folds, and layering.
- Preserve visible skin, hands, neck, legs, and feet exactly as in INPUT A unless covered by clothing.

––––––––––––––––––––––––––––––
7. LIGHTING & PHOTOGRAPHIC REALISM
––––––––––––––––––––––––––––––
- Match the lighting direction, intensity, and color temperature of INPUT A.
- Apply realistic contact shadows where clothing meets the body.
- Maintain a natural “shot on mobile phone” aesthetic.
- Avoid studio lighting, HDR effects, editorial styling, or artificial glow.

––––––––––––––––––––––––––––––
8. STRICT PROHIBITIONS
––––––––––––––––––––––––––––––
- Do NOT change face, hair, skin, body, pose, or background.
- Do NOT stylize, exaggerate, editorialize, or beautify.
- Do NOT alter image quality, sharpness, or perspective.
- Do NOT apply filters or color grading.

––––––––––––––––––––––––––––––
FINAL REQUIREMENT:
The final image must look like a real, unedited photo of the same person from INPUT A, wearing a new outfit that fulfills the user’s intent — taken at the same moment, in the same place, with the same camera.

OUTPUT:
Return ONLY the final transformed image.

''';

  @override
  Future<Uint8List> generateFromDescription({
    required Uint8List selfieImage,
    required String userDescription,
    required String targetColor,
    String selectedVibes = '',
    String contextTags = '',
  }) async {
    // Convert image to base64
    final selfieBase64 = base64Encode(selfieImage);

    // Build the request payload
    final payload = {
      'model': _model,
      'stream': false,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _buildDescribePrompt(userDescription, targetColor, selectedVibes, contextTags)},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$selfieBase64'}
            },
          ]
        }
      ]
    };

    // Make the API call
    final response = await http.post(
      Uri.parse(_apiUrl),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw DescribeOutfitException(
        'API request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    // Parse the response
    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;

    // Extract the image from the response
    final choices = responseJson['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw DescribeOutfitException('No choices in API response');
    }

    final message = choices[0]['message'] as Map<String, dynamic>?;
    if (message == null) {
      throw DescribeOutfitException('No message in API response');
    }

    final content = message['content'];

    // Handle different response formats using shared utility
    Uint8List? resultImage;

    if (content is String) {
      resultImage = ImageExtractionUtils.extractImageFromContent(content);
    } else if (content is List) {
      final List<Uint8List> foundImages = [];

      for (final part in content) {
        if (part is Map<String, dynamic>) {
          Uint8List? extractedImage;

          if (part['type'] == 'image' && part['image'] != null) {
            extractedImage = ImageExtractionUtils.decodeBase64Image(part['image'] as String);
          } else if (part['type'] == 'image_url') {
            final imageUrl = part['image_url'];
            if (imageUrl is Map && imageUrl['url'] != null) {
              extractedImage = ImageExtractionUtils.extractImageFromUrl(imageUrl['url'] as String);
            }
          } else if (part['type'] == 'inline_data' && part['data'] != null) {
            extractedImage = ImageExtractionUtils.decodeBase64Image(part['data'] as String);
          }

          if (extractedImage != null) {
            foundImages.add(extractedImage);
          }
        }
      }

      // Use the LAST image found (most likely the generated result)
      if (foundImages.isNotEmpty) {
        resultImage = foundImages.last;
      }
    } else if (content is Map<String, dynamic>) {
      if (content['image'] != null) {
        resultImage = ImageExtractionUtils.decodeBase64Image(content['image'] as String);
      }
    }

    if (resultImage == null) {
      throw DescribeOutfitException(
        'Could not extract image from API response. Response: ${response.body.substring(0, 500)}...',
      );
    }

    return resultImage;
  }
}

/// Exception thrown when describe hairstyle generation fails
class DescribeOutfitException implements Exception {
  final String message;
  DescribeOutfitException(this.message);

  @override
  String toString() => 'DescribeOutfitException: $message';
}

/// Mock implementation that simulates API delay (for testing)
class MockOutfitService implements OutfitService {
  @override
  Future<Uint8List> generateOutfit({
    required Uint8List selfieImage,
    required Uint8List referenceImage,
  }) async {
    // Simulate API processing delay
    await Future.delayed(const Duration(seconds: 3));

    // Return selfie as placeholder
    return selfieImage;
  }
}

// ============================================================================
// SECURE FIREBASE CLOUD FUNCTIONS IMPLEMENTATIONS
// ============================================================================

/// Secure implementation using Firebase Cloud Functions for hairstyle generation
/// API key is stored securely in Firebase Secret Manager
///
/// RATE LIMITING (enforced server-side):
/// - 15-second cooldown between generations
/// - Maximum 3 concurrent generations per user
/// - Credits only consumed on successful generation
class FirebaseOutfitService implements OutfitService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  Future<Uint8List> generateOutfit({
    required Uint8List selfieImage,
    required Uint8List referenceImage,
  }) async {
    final callable = _functions.httpsCallable(
      'generateOutfit',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );

    try {
      final result = await callable.call({
        'selfieBase64': base64Encode(selfieImage),
        'referenceBase64': base64Encode(referenceImage),
      });

      final imageBase64 = result.data['imageBase64'] as String;
      return base64Decode(imageBase64);
    } on FirebaseFunctionsException catch (e) {
      // Handle rate limiting errors (uses shared helper at bottom of file)
      handleRateLimitErrors(e);

      throw OutfitGenerationException(
        'Cloud function error: ${e.code} - ${e.message}',
      );
    }
  }
}

/// Secure implementation using Firebase Cloud Functions for hair color change
///
/// RATE LIMITING (enforced server-side):
/// - 15-second cooldown between generations
/// - Maximum 3 concurrent generations per user
/// - Credits only consumed on successful generation
class FirebaseOutfitStyleService implements OutfitStyleService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  Future<Uint8List> changeOutfitStyle({
    required Uint8List selfieImage,
    required List<Uint8List> clothingItems,
  }) async {
    final callable = _functions.httpsCallable(
      'changeOutfitStyle',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );

    try {
      // Convert clothing items to base64 list
      final clothingItemsBase64 = clothingItems.map((item) => base64Encode(item)).toList();

      final result = await callable.call({
        'selfieBase64': base64Encode(selfieImage),
        'clothingItemsBase64': clothingItemsBase64,
      });

      final imageBase64 = result.data['imageBase64'] as String;
      return base64Decode(imageBase64);
    } on FirebaseFunctionsException catch (e) {
      // Handle rate limiting errors
      handleRateLimitErrors(e);

      throw OutfitStyleChangeException(
        'Cloud function error: ${e.code} - ${e.message}',
      );
    }
  }
}

/// Secure implementation using Firebase Cloud Functions for text-described hairstyle
///
/// RATE LIMITING (enforced server-side):
/// - 15-second cooldown between generations
/// - Maximum 3 concurrent generations per user
/// - Credits only consumed on successful generation
class FirebaseDescribeOutfitService implements DescribeOutfitService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  Future<Uint8List> generateFromDescription({
    required Uint8List selfieImage,
    required String userDescription,
    required String targetColor,
    String selectedVibes = '',
    String contextTags = '',
  }) async {
    final callable = _functions.httpsCallable(
      'generateFromDescription',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );

    try {
      final result = await callable.call({
        'selfieBase64': base64Encode(selfieImage),
        'userDescription': userDescription,
        'targetColor': targetColor,
        'selectedVibes': selectedVibes,
        'contextTags': contextTags,
      });

      final imageBase64 = result.data['imageBase64'] as String;
      return base64Decode(imageBase64);
    } on FirebaseFunctionsException catch (e) {
      // Handle rate limiting errors
      handleRateLimitErrors(e);

      throw DescribeOutfitException(
        'Cloud function error: ${e.code} - ${e.message}',
      );
    }
  }
}

// ============================================================================
// FREE ONBOARDING GENERATION SERVICE (NO CREDIT CONSUMPTION)
// ============================================================================

/// Exception thrown when free onboarding generation was already used
class OnboardingGenerationUsedException implements Exception {
  final String message;

  OnboardingGenerationUsedException({
    this.message = 'Free onboarding generation already used',
  });

  @override
  String toString() => 'OnboardingGenerationUsedException: $message';
}

/// Service for FREE hairstyle generation during onboarding
/// This does NOT consume any credits - it's a one-time free generation
///
/// After this generation, users still have their full 2 free credits
class FirebaseOnboardingOutfitService implements DescribeOutfitService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  @override
  Future<Uint8List> generateFromDescription({
    required Uint8List selfieImage,
    required String userDescription,
    required String targetColor,
    String selectedVibes = '',
    String contextTags = '',
  }) async {
    final callable = _functions.httpsCallable(
      'generateOnboardingOutfit',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );

    try {
      final result = await callable.call({
        'selfieBase64': base64Encode(selfieImage),
        'userDescription': userDescription,
        'targetColor': targetColor,
        'selectedVibes': selectedVibes,
        'contextTags': contextTags,
      });

      final imageBase64 = result.data['imageBase64'] as String;
      return base64Decode(imageBase64);
    } on FirebaseFunctionsException catch (e) {
      // Handle "already used" error specifically
      if (e.code == 'failed-precondition') {
        throw OnboardingGenerationUsedException(
          message: e.message ?? 'Free onboarding generation already used',
        );
      }

      // Handle other rate limiting errors
      handleRateLimitErrors(e);

      throw DescribeOutfitException(
        'Cloud function error: ${e.code} - ${e.message}',
      );
    }
  }
}

// ============================================================================
// SHARED RATE LIMIT ERROR HANDLER
// ============================================================================

/// Handle rate limiting error codes from the server
/// Throws appropriate exceptions for rate limit errors
void handleRateLimitErrors(FirebaseFunctionsException e) {
  if (e.code == 'resource-exhausted') {
    final details = e.details;
    if (details is Map) {
      final errorCode = details['errorCode'] as String?;
      final currentCredits = details['currentCredits'] as int?;
      final retryAfterSeconds = details['retryAfterSeconds'] as int?;

      switch (errorCode) {
        case 'cooldown':
          throw RateLimitCooldownException(
            retryAfterSeconds: retryAfterSeconds ?? 15,
            message: e.message ?? 'Please wait a moment before generating again',
          );
        case 'concurrent_limit':
          throw ConcurrentLimitException(
            message: e.message ?? 'Too many requests in progress',
          );
        case 'insufficient_credits':
          throw InsufficientCreditsException(
            currentCredits: currentCredits ?? 0,
            requiredCredits: 1,
          );
      }
    }

    // Fallback for insufficient credits detection via message
    if (e.message?.contains('Insufficient credits') ?? false) {
      final regex = RegExp(r'You have (\d+) credits');
      final match = regex.firstMatch(e.message ?? '');
      final currentCredits =
          match != null ? int.tryParse(match.group(1) ?? '0') ?? 0 : 0;
      throw InsufficientCreditsException(
        currentCredits: currentCredits,
        requiredCredits: 1,
      );
    }
  }
}
