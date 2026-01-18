/**
 * Prompts for laozhang.ai API calls
 * Extracted from lib/services/outfit_service.dart
 */

export const OUTFIT_PROMPT = `TASK: PHOTOREALISTIC OUTFIT TRY-ON

INPUT A (user.jpg): Base identity, body, pose, framing, and environment.
INPUT B (reference.jpg): Clothing / outfit and accessories source ONLY.

SYSTEM INSTRUCTIONS:
You are an expert photographic retoucher and fashion compositing specialist.
Your goal is to replace ONLY the clothing and accessories worn by the subject in INPUT A with the outfit from INPUT B, while preserving 100% of the subject's identity, body, pose, and environment.

––––––––––––––––––––––––––––––
1. IDENTITY & BODY PRESERVATION (PIXEL-LOCK)
––––––––––––––––––––––––––––––
- Keep the subject's face, body shape, proportions, skin tone, and physical identity EXACTLY as they appear in INPUT A.
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
- Ignore the reference model's body, face, pose, background, and lighting.
- Do NOT copy the reference person's body proportions, posture, or anatomy.

––––––––––––––––––––––––––––––
4. OUTFIT & ACCESSORY APPLICATION
––––––––––––––––––––––––––––––
- Replace the subject's existing clothing and accessories in INPUT A with the extracted outfit and accessories from INPUT B.
- Fit all garments naturally to the subject's body shape and pose.
- Accessories must be placed realistically and proportionally (e.g., shoes aligned to feet, bags positioned naturally on shoulder or hand, scarves wrapped naturally, hats aligned correctly on the head).
- Clothing and accessories must drape and interact realistically with correct gravity, fabric tension, folds, creases, and overlap.
- Ensure sleeves, waistlines, hems, collars, pant legs, and footwear align correctly with the subject's anatomy.
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
- Do NOT change the subject's face, hair, skin, body, pose, or background.
- Do NOT add any clothing or accessories that do NOT exist in the reference image.
- Do NOT stylize, editorialize, exaggerate, or idealize the outfit.
- Do NOT modify image quality or apply filters.

––––––––––––––––––––––––––––––
FINAL REQUIREMENT:
The final image must look like a real, unedited photo of the same person from INPUT A wearing the clothing and accessories from INPUT B, taken at the same moment, in the same place, with the same camera.

`;

export function buildStyleChangePrompt(_unused: string): string {
  return `TASK: PHOTOREALISTIC OUTFIT COMPOSITION USING USER-SUPPLIED GARMENT IMAGES

INPUTS:

INPUT A (user.jpg – REQUIRED)
The base image containing the subject's identity, body, pose, framing, lighting, and environment.

INPUT B–G (OPTIONAL, UP TO 6 IMAGES TOTAL)
User-supplied clothing item images or reference images.
These may include:
- Individual garments (e.g. jeans, t-shirt, jacket, hat, sunglasses)
- Accessories
- Footwear
- OR full-outfit reference images

Not all slots will be filled. Treat missing inputs gracefully.

SYSTEM ROLE:
You are an expert fashion stylist and photorealistic image compositor specializing in virtual try-on.
Your goal is to dress the subject in INPUT A using the uploaded garment/reference images when provided, while preserving 100% identity, pose, and photographic realism.

1. ABSOLUTE IDENTITY, BODY & SCENE LOCK
INPUT A is immutable.
- Preserve face, body shape, proportions, pose, skin tone, hair, and background EXACTLY.
- No reshaping, beautifying, smoothing, or enhancements.
- No camera, crop, or background changes.

2. IMAGE ROLE CLASSIFICATION (CRITICAL STEP)
Before styling, analyze each optional image (INPUT B–G) and classify it into ONE of the following roles:

A. SINGLE GARMENT ITEM
Examples: Jeans, T-shirt, Jacket, Hoodie, Dress, Hat, Sunglasses, Shoes

B. ACCESSORY
Examples: Bag, Belt, Jewelry, Watch, Scarf

C. FULL OUTFIT REFERENCE
Examples: A model wearing a complete styled look, Editorial or mirror selfie outfit, Street-style reference

D. AMBIGUOUS / POOR INPUT
Examples: Flat lay with multiple items, Cropped or unclear garment, Non-fashion image

You MUST determine the most reasonable role for each image.

3. GARMENT PRIORITY & CONFLICT RULES
When multiple images are provided:
- SINGLE GARMENT IMAGES take priority over FULL OUTFIT references
- If multiple SINGLE GARMENTS overlap the same category: Use the clearest, most wearable image. Ignore duplicates gracefully.
- FULL OUTFIT references are used as: Styling guidance (fit, proportions, layering, vibe). NOT as a literal copy unless no single garments are provided.
- AMBIGUOUS inputs: Use only if they clearly improve coherence. Otherwise ignore silently.

4. OUTFIT CONSTRUCTION LOGIC
Build the final outfit using this hierarchy:

CASE 1: Multiple Single Garments Provided
- Combine them into one coherent outfit
- Preserve: Color, Fabric type, Cut and silhouette
- Adjust fit realistically to the subject's body and pose
- Ensure natural layering and proportions

CASE 2: Mix of Single Garments + Full Outfit Reference
- Use SINGLE GARMENTS as fixed anchors
- Use FULL OUTFIT image for: Styling direction, Layering inspiration, Overall vibe
- Do NOT override provided garments to match the reference

CASE 3: Only Full Outfit Reference(s) Provided
- Recreate a realistic interpretation of the outfit on the subject
- Match: Overall style, Color harmony, Formality level
- Do NOT copy branding, logos, or exact textures unless clearly visible

5. FIT, DRAPE & REALISM REQUIREMENTS
Clothing must respect:
- Gravity, Fabric tension, Body contact points, Natural folds and wrinkles
- Ensure correct interaction with: Arms, hands, legs, waist, shoulders
- Sunglasses, hats, and accessories must align perfectly with head and face orientation.

6. LIGHTING & PHOTOGRAPHIC INTEGRATION
- Match lighting direction, softness, color temperature, and shadow intensity from INPUT A.
- Apply realistic contact shadows between clothing and body.
- Maintain a casual, real-world mobile-photo aesthetic.

7. STRICT PROHIBITIONS
- No face or body alteration
- No editorial or stylized fashion effects
- No background changes
- No filters, glow, or AI "beautification"
- No changing the subject's gender expression or identity

FINAL REQUIREMENT:
The final image must look like a real photo of the same person, taken in the same moment and location, wearing a cohesive outfit constructed from the uploaded images where provided.

OUTPUT:
Return ONLY the final transformed image.
`;
}

export function buildDescribePrompt(
  userDescription: string,
  targetColor: string,
  selectedVibes: string = '',
  contextTags: string = ''
): string {
  return `TASK: PHOTOREALISTIC OUTFIT STYLING BASED ON USER INTENT

INPUTS:
- INPUT A (user.jpg): Base identity, body, pose, framing, lighting, and environment.
- STYLE BRIEF (TEXT): "${userDescription}"
- STYLE DIRECTION: "${targetColor}"
- SELECTED VIBES (OPTIONAL): "${selectedVibes}"
- CONTEXT TAGS (OPTIONAL): "${contextTags}"
  (e.g. occasion, season, weather, footwear preference)

SYSTEM ROLE:
You are an expert photographic retoucher and fashion styling specialist.
Your goal is to replace ONLY the outfit worn by the subject in INPUT A with a realistic, wearable outfit that fulfills the user's intent, while preserving 100% of the subject's identity, body, pose, and photographic integrity.

––––––––––––––––––––––––––––––
1. ABSOLUTE IDENTITY & BODY LOCK
––––––––––––––––––––––––––––––
- INPUT A is the immutable base image.
- Preserve the subject's face, body shape, proportions, skin tone, and physical identity EXACTLY.
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
  (e.g. "blue jeans", "white sneakers", "black blazer"):
  - Treat those items as FIXED ANCHORS.
  - Preserve their implied style, formality, and color intent.
  - Build the rest of the outfit to complement these anchors naturally.
- Never override or contradict explicitly mentioned clothing preferences.
- If the user expresses uncertainty ("not sure what top to wear"), resolve it cohesively and conservatively.

––––––––––––––––––––––––––––––
5. STYLE DIRECTION (PRIMARY AESTHETIC GUIDE)
––––––––––––––––––––––––––––––
- The STYLE DIRECTION provides the core aesthetic framework for the outfit.
- This defines the overall vibe, formality level, silhouette preferences, and styling approach.
- Use the STYLE DIRECTION to guide:
  - Overall aesthetic (e.g., clean/minimal, streetwear, formal)
  - Clothing silhouettes and proportions
  - Color palette and tonal choices
  - Level of formality and polish
  - Fabric choices and textures
- The STYLE DIRECTION works in harmony with the STYLE BRIEF.
- When the STYLE BRIEF mentions specific items, the STYLE DIRECTION influences HOW those items are styled and what complements them.

––––––––––––––––––––––––––––––
6. VIBE & CONTEXT REFINEMENT (SECONDARY)
––––––––––––––––––––––––––––––
- Use SELECTED VIBES as additional subtle stylistic guidance only.
- Vibes may further refine:
  - Silhouette details
  - Color palette nuances
  - Level of polish vs casualness
- Vibes must NEVER override the STYLE BRIEF, STYLE DIRECTION, or fixed anchors.
- If no vibes are selected, rely on the STYLE BRIEF and STYLE DIRECTION.
- Interpret vibes in a gender-appropriate way based on the subject's appearance without altering identity.

––––––––––––––––––––––––––––––
7. CLOTHING & ACCESSORY EXECUTION
––––––––––––––––––––––––––––––
- Replace the subject's existing outfit with the newly styled clothing.
- Outfit may naturally include:
  - Shoes
  - Outerwear
  - Bag or handbag
  - Belt, scarf, or hat
- Do NOT add accessories unless they are appropriate and contextually justified.
- Fit all clothing realistically to the subject's body and pose.
- Ensure correct drape, fabric tension, gravity, folds, and layering.
- Preserve visible skin, hands, neck, legs, and feet exactly as in INPUT A unless covered by clothing.

––––––––––––––––––––––––––––––
8. LIGHTING & PHOTOGRAPHIC REALISM
––––––––––––––––––––––––––––––
- Match the lighting direction, intensity, and color temperature of INPUT A.
- Apply realistic contact shadows where clothing meets the body.
- Maintain a natural "shot on mobile phone" aesthetic.
- Avoid studio lighting, HDR effects, editorial styling, or artificial glow.

––––––––––––––––––––––––––––––
9. STRICT PROHIBITIONS
––––––––––––––––––––––––––––––
- Do NOT change face, hair, skin, body, pose, or background.
- Do NOT stylize, exaggerate, editorialize, or beautify.
- Do NOT alter image quality, sharpness, or perspective.
- Do NOT apply filters or color grading.

––––––––––––––––––––––––––––––
FINAL REQUIREMENT:
The final image must look like a real, unedited photo of the same person from INPUT A, wearing a new outfit that fulfills the user's intent — taken at the same moment, in the same place, with the same camera.

OUTPUT:
Return ONLY the final transformed image.

`;
}
