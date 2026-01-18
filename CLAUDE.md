# Outfiti - Project Context for Claude

## App Overview
**Outfiti** is an AI-powered outfit try-on app. Users can upload photos and virtually try on different outfits using AI generation.

## Important: Rebranding History
This app was **refactored and rebranded** from a Hair AI app to Outfiti. The core structure was migrated but the concept changed:

**Before:** Hair AI Salon - virtual hairstyle try-on
**After:** Outfiti - AI outfit try-on and outfit maker

### Key Configuration
- **Firebase Project:** `outfiti-444` (DO NOT touch other Firebase projects)
- **Package Name:** `com.outfiti.app` (Android & iOS)
- **App Name:** Outfiti

### Naming Conventions
The refactoring updated most code to use outfit-related terminology:
- `OutfitTryOnProvider` (state management)
- `OutfitService` (AI generation service)
- `OutfitStyleData` (outfit data models)
- `generateOutfit()` (main generation method)
- File locations: `outfit_samples/`, `outfit_try_on_screen.dart`, etc.

### What Still Needs Updates
When implementing new features or fixing issues, be aware:

1. **AI Prompts** - Some prompts in `outfit_service.dart` may still reference hairstyles instead of outfits
2. **Sample Images** - The `outfit_samples/` folder may contain old hair-related images
3. **UI Text** - Some screens may have legacy hair-specific language
4. **Comments/Documentation** - Code comments might reference the old domain

### Development Guidelines
- Use **outfit** terminology, not hair/hairstyle
- Reference the `outfiti-444` Firebase project only
- Follow existing patterns in refactored files like `outfit_try_on_screen.dart` and `outfit_service.dart`
- When in doubt about naming, check similar existing files for consistency

## Tech Stack
- Flutter/Dart
- Firebase (Auth, Firestore, Storage)
- RevenueCat (subscriptions)
- AI image generation (outfit try-on)

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

```bash
# Flutter commands
flutter pub get              # Install dependencies
flutter analyze              # Run static analysis (ALWAYS run after changes)
flutter build ios            # Build iOS app
flutter build apk            # Build Android APK
flutter run                  # Run app on connected device

# Firebase Cloud Functions (from functions/ directory)
cd functions
npm install                  # Install function dependencies
npm run build                # Compile TypeScript
firebase deploy --only functions  # Deploy functions

# Firebase Secrets (required for API)
firebase functions:secrets:set LAOZHANG_API_KEY  # Set API key in Secret Manager
```

## Architecture Overview

### Flutter App (lib/)

**State Management**: Uses Provider pattern with ChangeNotifier
- `ThemeProvider` - Multi-theme system with 9 color themes, persisted via SharedPreferences
- `AuthProvider` - Firebase Authentication state
- `GalleryRefreshNotifier` - Cross-screen gallery sync

**Service Layer**: Abstract interfaces with Firebase implementations
- `OutfitService` / `FirebaseOutfitService` - Reference outfit copy (2 images: selfie + reference)
- `OutfitStyleService` / `FirebaseOutfitStyleService` - Multi-garment try-on (1 selfie + up to 6 clothing items)
- `DescribeOutfitService` / `FirebaseDescribeOutfitService` - Text-to-outfit generation
- `CreditService` - User credit management for API calls
- `GalleryService` - Firebase Storage image gallery

**Navigation**: Tab-based with `HomeNavBar` containing:
- Describe screen (text-based outfit generation)
- AI Try-On screen (multi-garment upload)
- Outfit Try-On screen (reference-based copy)
- Gallery screen (saved results)
- Profile screen (settings, themes)

### Screen → Service → Function → Prompt Mapping

**CRITICAL**: This app has THREE distinct outfit generation features. Each uses a different prompt and function.

#### 1. Describe Screen (`lib/screens/describe_screen.dart`)
**Purpose**: Generate outfit from text description + style vibes
- **Service**: `DescribeOutfitService` → `FirebaseDescribeOutfitService`
- **Cloud Function**: `generateFromDescription` (functions/src/index.ts)
- **Prompt Location**: `functions/src/prompts.ts` → `buildDescribePrompt()`
- **Input**: 1 selfie + text description + vibes/tags
- **Output**: Styled outfit based on text description

#### 2. AI Try-On Screen (`lib/screens/ai_try_on_screen.dart`)
**Purpose**: Upload multiple clothing items (1-6) and see them combined on your photo
- **Service**: `OutfitStyleService` → `FirebaseOutfitStyleService`
- **Cloud Function**: `changeOutfitStyle` (functions/src/index.ts)
- **Prompt Location**: `functions/src/prompts.ts` → `buildStyleChangePrompt()`
- **Input**: 1 selfie + 1-6 clothing item images
- **Output**: Subject wearing the combined outfit from uploaded items
- **Key Feature**: AI classifies each image (single garment vs full outfit) and combines intelligently

#### 3. Outfit Try-On Screen (`lib/screens/outfit_try_on_screen.dart`)
**Purpose**: Copy an outfit from a reference image onto your photo
- **Service**: `OutfitService` → `FirebaseOutfitService`
- **Cloud Function**: `generateOutfit` (functions/src/index.ts)
- **Prompt Location**: `functions/src/prompts.ts` → `OUTFIT_PROMPT` (constant)
- **Input**: 1 selfie + 1 reference image (full outfit)
- **Output**: Subject wearing the exact outfit from the reference image

### Firebase Backend (functions/src/)

TypeScript Cloud Functions proxying to laozhang.ai image generation API:
- `generateOutfit` - Copy outfit from reference image (2 images)
- `changeOutfitStyle` - Multi-garment virtual try-on (1 selfie + up to 6 garments)
- `generateFromDescription` - Text-described outfit generation
- `generateOnboardingOutfit` - Free onboarding generation (no credits)
- Credit system functions (initializeUserCredits, consumeCredit, etc.)

API key stored in Firebase Secret Manager (`LAOZHANG_API_KEY`).

**Prompt Files**:
- `functions/src/prompts.ts` - Contains all AI prompts
  - `OUTFIT_PROMPT` - Reference outfit copy (used by generateOutfit)
  - `buildStyleChangePrompt()` - Multi-garment try-on (used by changeOutfitStyle)
  - `buildDescribePrompt()` - Text-to-outfit (used by generateFromDescription)

### Important Notes on Naming & Refactoring History

**Why the naming might seem confusing**:
This app was refactored from "Hair AI Salon" (hair try-on) to "Outfiti" (outfit try-on). During refactoring:
- Most code was updated to use outfit terminology
- Some legacy names remain in prompts and internal variables
- The core structure (3 generation modes) stayed the same, just changed domain

**Function Name Clarification**:
- `generateOutfit()` - Despite the generic name, this is specifically for **reference image copying** (not multi-garment)
- `changeOutfitStyle()` - Despite sounding like a style change, this is for **multi-garment try-on**
- `generateFromDescription()` - This is for **text-based generation**

**When modifying prompts**:
1. Always check `functions/src/prompts.ts` FIRST - this is the source of truth
2. The Dart service files (`lib/services/outfit_service.dart`) contain deprecated/legacy prompts for reference only
3. Only the TypeScript prompts in `functions/src/prompts.ts` are used in production

## UI/UX Guidelines

### Button Visibility and Contrast
**CRITICAL**: Always ensure button text is clearly visible against its background.

#### Theme Color Reference for HairAI
**CRITICAL**: This project uses a custom theme structure where:
- `colorScheme.primary` = Surface/background color (e.g., dark backgrounds in dark themes)
- `colorScheme.secondary` = **ACCENT color** (e.g., gold, pink, cyan - the bright highlight color)

**ALWAYS use `colorScheme.secondary` for accent colors, NOT `colorScheme.primary`!**

#### Alternate/Outlined Buttons (OutlinedButton, TextButton)
**ALWAYS explicitly set text color to accent from theme provider**

```dart
OutlinedButton(
  style: OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(56),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
  ),
  child: Text(
    'Button Text',
    style: TextStyle(
      color: theme.colorScheme.secondary, // ✅ REQUIRED - Accent color (NOT primary!)
      fontWeight: FontWeight.w600,
    ),
  ),
)
```

#### Filled Buttons (FilledButton)
**FilledButton automatically handles colors correctly**
- Background and text colors are automatically set by Material 3
- Generally no manual color override needed unless specific design requirement

```dart
FilledButton(
  style: FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(56),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
  ),
  child: const Text('Button Text'),
)
```

**Why**: In this project's theme setup, outlined buttons with default styling will have text in `primary` color which is the same as the surface/background, making text invisible. You must use `secondary` which contains the actual accent color.

### Animation Best Practices

**Avoid Repeating Animations on Final States**
- ❌ **DON'T**: Use `.animate(onPlay: (controller) => controller.repeat(reverse: true))` on result/final screens
- ✅ **DO**: Use one-time entry animations with `fadeIn()` and `scale()` for smooth transitions
- **Why**: Constantly repeating animations (flashing, pulsing) on final results are distracting and reduce user experience

**Example of Good Entry Animation**:
```dart
Widget.animate()
  .fadeIn(duration: 600.ms, curve: Curves.easeOut)
  .scale(
    begin: const Offset(0.95, 0.95),
    end: const Offset(1.0, 1.0),
    duration: 600.ms,
    curve: Curves.easeOut,
  )
```

### Text Overflow Prevention

**Always Wrap Long Text in Flexible/Expanded**
- When using `Row` or `Column` with text that might be long, wrap the `Text` widget in `Flexible` or `Expanded`
- Use shorter, concise text when possible
- Consider `textAlign: TextAlign.center` for centered containers

**Example**:
```dart
Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(...),
    const SizedBox(width: 8),
    Flexible(  // ✅ Prevents overflow
      child: Text(
        'Your text here',
        style: ...,
      ),
    ),
  ],
)
```

### Color Opacity Updates

**Use `.withValues(alpha: value)` instead of `.withOpacity(value)`**
- The `.withOpacity()` method is deprecated in newer Flutter versions
- Replace with `.withValues(alpha: 0.5)` for alpha transparency
- **Why**: Avoids precision loss and follows Flutter's latest API

**Example**:
```dart
// ❌ Old way (deprecated)
color: colorScheme.outline.withOpacity(0.3)

// ✅ New way
color: colorScheme.outline.withValues(alpha: 0.3)
```

## Code Quality

### Always Run Flutter Analyze
- Run `flutter analyze` after making changes
- Fix all warnings and errors before considering a task complete
- Pay special attention to:
    - Deprecated API usage
    - Unused variables
    - Potential overflow issues
    - BuildContext usage across async gaps

### State Management
- Reset relevant state when user uploads new images
- Use `mounted` check before calling `setState` in async operations
- Properly dispose controllers and clean up resources

## Testing Checklist

Before marking a UI task as complete, verify:
- [ ] All buttons are clearly visible with proper contrast
- [ ] No text overflow errors
- [ ] Animations play smoothly without distracting repetitions
- [ ] No deprecated API warnings in `flutter analyze`
- [ ] UI works on different screen sizes
- [ ] Colors follow Material 3 theme guidelines

## Common Patterns in This Project

### Image Upload Cards
- Use `Material` with `InkWell` for proper ripple effects
- Height: 240px for consistency
- Border radius: 20px for cards, 12px for inner content
- Show placeholder with icon when empty
- Use `Image.memory()` for displaying uploaded images

### Generate/Action Buttons
- Minimum height: 56px
- Border radius: 16px
- Show loading indicator when processing
- Disable button during async operations
- Use `FilledButton` for primary actions
- Use `OutlinedButton` or `FilledButton.tonal` for secondary actions

### Spacing
- Screen padding: 24px
- Card spacing: 20px between cards
- Content spacing: 8-12px for related items, 24-32px for sections
- Button row gap: 12px

---

**Last Updated**: 2025-12-23
**Version**: 1.2
