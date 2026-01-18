/**
 * Utility functions for image extraction from API responses
 */

/**
 * Extract base64 image from API response content
 * Handles multiple response formats from the laozhang.ai API
 */
export function extractImageFromContent(content: unknown): string | null {
  // Handle string content
  if (typeof content === 'string') {
    return extractImageFromString(content);
  }

  // Handle array content (multiple parts)
  if (Array.isArray(content)) {
    const foundImages: string[] = [];

    for (const part of content) {
      if (typeof part === 'object' && part !== null) {
        const obj = part as Record<string, unknown>;
        let extractedImage: string | null = null;

        if (obj.type === 'image' && typeof obj.image === 'string') {
          extractedImage = cleanBase64(obj.image);
        } else if (obj.type === 'image_url') {
          const imageUrl = obj.image_url as Record<string, unknown> | undefined;
          if (imageUrl && typeof imageUrl.url === 'string') {
            extractedImage = extractImageFromDataUri(imageUrl.url);
          }
        } else if (obj.type === 'inline_data' && typeof obj.data === 'string') {
          extractedImage = cleanBase64(obj.data);
        }

        if (extractedImage) {
          foundImages.push(extractedImage);
        }
      }
    }

    // Return the LAST image found (most likely the generated result, not echoed inputs)
    if (foundImages.length > 0) {
      return foundImages[foundImages.length - 1];
    }
  }

  // Handle object content
  if (typeof content === 'object' && content !== null) {
    const obj = content as Record<string, unknown>;
    if (typeof obj.image === 'string') {
      return cleanBase64(obj.image);
    }
  }

  return null;
}

/**
 * Extract base64 image from string content
 */
function extractImageFromString(content: string): string | null {
  // Method 1: Find data URI and extract everything after "base64,"
  const base64Marker = 'base64,';
  const markerIndex = content.indexOf(base64Marker);
  if (markerIndex !== -1) {
    let remaining = content.substring(markerIndex + base64Marker.length);

    // Find the end of the base64 data
    let endIndex = remaining.length;
    const delimiters = [')', ']', '"', "'", '\n', ' '];
    for (const delimiter of delimiters) {
      const idx = remaining.indexOf(delimiter);
      if (idx !== -1 && idx < endIndex) {
        endIndex = idx;
      }
    }

    const base64Data = remaining.substring(0, endIndex);
    if (isValidBase64(base64Data)) {
      return cleanBase64(base64Data);
    }
  }

  // Method 2: Check for markdown image format
  const markdownMatch = content.match(/!\[.*?\]\(\s*data:image\/[^;]+;base64,([A-Za-z0-9+/=\s]+)\s*\)/);
  if (markdownMatch) {
    return cleanBase64(markdownMatch[1]);
  }

  // Method 3: Check for data URI format
  const dataUriMatch = content.match(/data:image\/[^;]+;base64,([A-Za-z0-9+/=\s]+)/);
  if (dataUriMatch) {
    return cleanBase64(dataUriMatch[1]);
  }

  // Method 4: Direct base64 string (long string without spaces/newlines)
  if (content.length > 100 && !content.includes(' ') && !content.includes('\n')) {
    if (isValidBase64(content)) {
      return cleanBase64(content);
    }
  }

  return null;
}

/**
 * Extract base64 from data URI
 */
function extractImageFromDataUri(url: string): string | null {
  if (url.startsWith('data:image')) {
    const parts = url.split('base64,');
    if (parts.length === 2) {
      return cleanBase64(parts[1]);
    }
  }
  return null;
}

/**
 * Clean base64 string by removing whitespace and data URI prefix
 */
function cleanBase64(base64String: string): string {
  let cleaned = base64String.trim();

  // Remove data URI prefix if present
  if (cleaned.includes('base64,')) {
    cleaned = cleaned.split('base64,')[1];
  }

  // Remove whitespace/newlines
  cleaned = cleaned.replace(/\s/g, '');

  return cleaned;
}

/**
 * Check if string is valid base64
 */
function isValidBase64(str: string): boolean {
  if (!str || str.length === 0) return false;

  // Remove whitespace for validation
  const cleaned = str.replace(/\s/g, '');

  // Check if it only contains valid base64 characters
  const base64Regex = /^[A-Za-z0-9+/]*={0,2}$/;
  return base64Regex.test(cleaned) && cleaned.length > 0;
}
