/*
 * Copyright 2006 Jeremias Maerki in part, and ZXing Authors in part
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "ZXErrors.h"
#import "ZXPDF417HighLevelEncoder.h"

/**
 * code for Text compaction
 */
const int TEXT_COMPACTION = 0;

/**
 * code for Byte compaction
 */
const int BYTE_COMPACTION = 1;

/**
 * code for Numeric compaction
 */
const int NUMERIC_COMPACTION = 2;

/**
 * Text compaction submode Alpha
 */
const int SUBMODE_ALPHA = 0;

/**
 * Text compaction submode Lower
 */
const int SUBMODE_LOWER = 1;

/**
 * Text compaction submode Mixed
 */
const int SUBMODE_MIXED = 2;

/**
 * Text compaction submode Punctuation
 */
const int SUBMODE_PUNCTUATION = 3;

/**
 * mode latch to Text Compaction mode
 */
const int LATCH_TO_TEXT = 900;

/**
 * mode latch to Byte Compaction mode (number of characters NOT a multiple of 6)
 */
const int LATCH_TO_BYTE_PADDED = 901;

/**
 * mode latch to Numeric Compaction mode
 */
const int LATCH_TO_NUMERIC = 902;

/**
 * mode shift to Byte Compaction mode
 */
const int SHIFT_TO_BYTE = 913;

/**
 * mode latch to Byte Compaction mode (number of characters a multiple of 6)
 */
const int LATCH_TO_BYTE = 924;

/**
 * Raw code table for text compaction Mixed sub-mode
 */
const int TEXT_MIXED_RAW_LEN = 30;
const unsigned char TEXT_MIXED_RAW[TEXT_MIXED_RAW_LEN] = {
  48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 38, 13, 9, 44, 58,
  35, 45, 46, 36, 47, 43, 37, 42, 61, 94, 0, 32, 0, 0, 0};

/**
 * Raw code table for text compaction: Punctuation sub-mode
 */
const int TEXT_PUNCTUATION_RAW_LEN = 30;
const unsigned char TEXT_PUNCTUATION_RAW[TEXT_PUNCTUATION_RAW_LEN] = {
  59, 60, 62, 64, 91, 92, 93, 95, 96, 126, 33, 13, 9, 44, 58,
  10, 45, 46, 36, 47, 34, 124, 42, 40, 41, 63, 123, 125, 39, 0};

const int MIXED_TABLE_LEN = 128;
unichar MIXED_TABLE[MIXED_TABLE_LEN] = {0};

const int PUNCTUATION_LEN = 128;
unichar PUNCTUATION[PUNCTUATION_LEN] = {0};

@interface ZXPDF417HighLevelEncoder ()

+ (unsigned char*)bytesForMessage:(NSString*)msg;
+ (int)encodeText:(NSString*)msg startpos:(int)startpos count:(int)count buffer:(NSMutableString*)sb initialSubmode:(int)initialSubmode;
+ (void)encodeBinary:(unsigned char*)bytes startpos:(int)startpos count:(int)count startmode:(int)startmode buffer:(NSMutableString*)sb;
+ (void)encodeNumeric:(NSString*)msg startpos:(int)startpos count:(int)count buffer:(NSMutableString*)sb;
+ (BOOL)isDigit:(char)ch;
+ (BOOL)isAlphaUpper:(char)ch;
+ (BOOL)isAlphaLower:(char)ch;
+ (BOOL)isMixed:(char)ch;
+ (BOOL)isPunctuation:(char)ch;
+ (BOOL)isText:(char)ch;
+ (int)determineConsecutiveDigitCount:(NSString*)msg startpos:(int)startpos;
+ (int)determineConsecutiveTextCount:(NSString*)msg startpos:(int)startpos;
+ (int)determineConsecutiveBinaryCount:(NSString*)msg bytes:(unsigned char*)bytes startpos:(int)startpos error:(NSError**)error;

@end

@implementation ZXPDF417HighLevelEncoder

+ (void)initialize {
  //Construct inverse lookups
  for (int i = 0; i < MIXED_TABLE_LEN; i++) {
    MIXED_TABLE[i] = -1;
  }
  for (unsigned char i = 0; i < TEXT_MIXED_RAW_LEN; i++) {
    unsigned char b = TEXT_MIXED_RAW[i];
    if (b > 0) {
      MIXED_TABLE[b] = i;
    }
  }
  for (int i = 0; i < PUNCTUATION_LEN; i++) {
    PUNCTUATION[i] = -1;
  }
  for (unsigned char i = 0; i < TEXT_PUNCTUATION_RAW_LEN; i++) {
    unsigned char b = TEXT_PUNCTUATION_RAW[i];
    if (b > 0) {
      PUNCTUATION[b] = i;
    }
  }
}

/**
 * Converts the message to a byte array using the default encoding (cp437) as defined by the
 * specification
 */
+ (unsigned char*)bytesForMessage:(NSString*)msg {
  return (unsigned char*)[[msg dataUsingEncoding:(NSStringEncoding) 0x80000400] bytes];
}

/**
 * Performs high-level encoding of a PDF417 message using the algorithm described in annex P
 * of ISO/IEC 15438:2001(E).  If byte compaction has been selected, then only byte compaction
 * is used.
 */
+ (NSString*)encodeHighLevel:(NSString*)msg byteCompaction:(BOOL)byteCompaction error:(NSError**)error {
  unsigned char* bytes = NULL; //Fill later and only if needed

  //the codewords 0..928 are encoded as Unicode characters
  NSMutableString* sb = [NSMutableString stringWithCapacity:msg.length];

  int len = msg.length;
  int p = 0;
  int encodingMode = TEXT_COMPACTION; //Default mode, see 4.4.2.1
  int textSubMode = SUBMODE_ALPHA;
  if (byteCompaction) {
    encodingMode = BYTE_COMPACTION;
    while (p < len) {

      if (bytes == NULL) {
        bytes = [self bytesForMessage:msg];
      }
      int b = [self determineConsecutiveBinaryCount:msg bytes:bytes startpos:p error:error];
      if (b == -1) {
        return nil;
      } else if (b == 0) {
        b = 1;
      }
      if (b == 1 && encodingMode == TEXT_COMPACTION) {
        //Switch for one byte (instead of latch)
        [self encodeBinary:bytes startpos:p count:1 startmode:TEXT_COMPACTION buffer:sb];
      } else {
        //Mode latch performed by encodeBinary
        [self encodeBinary:bytes startpos:p count:b startmode:encodingMode buffer:sb];
        encodingMode = BYTE_COMPACTION;
        textSubMode = SUBMODE_ALPHA; //Reset after latch
      }
      p += b;
    }
  } else {
    while (p < len) {
      int n = [self determineConsecutiveDigitCount:msg startpos:p];
      if (n >= 13) {
        [sb appendFormat:@"%c", (char) LATCH_TO_NUMERIC];
        encodingMode = NUMERIC_COMPACTION;
        textSubMode = SUBMODE_ALPHA; //Reset after latch
        [self encodeNumeric:msg startpos:p count:n buffer:sb];
        p += n;
      } else {
        int t = [self determineConsecutiveTextCount:msg startpos:p];
        if (t >= 5 || n == len) {
          if (encodingMode != TEXT_COMPACTION) {
            [sb appendFormat:@"%c", (char) LATCH_TO_TEXT];
            encodingMode = TEXT_COMPACTION;
            textSubMode = SUBMODE_ALPHA; //start with submode alpha after latch
          }
          textSubMode = [self encodeText:msg startpos:p count:t buffer:sb initialSubmode:textSubMode];
          p += t;
        } else {
          if (bytes == NULL) {
            bytes = [self bytesForMessage:msg];
          }
          int b = [self determineConsecutiveBinaryCount:msg bytes:bytes startpos:p error:error];
          if (b == -1) {
            return nil;
          } else if (b == 0) {
            b = 1;
          }
          if (b == 1 && encodingMode == TEXT_COMPACTION) {
            //Switch for one byte (instead of latch)
            [self encodeBinary:bytes startpos:p count:1 startmode:TEXT_COMPACTION buffer:sb];
          } else {
            //Mode latch performed by encodeBinary
            [self encodeBinary:bytes startpos:p count:b startmode:encodingMode buffer:sb];
            encodingMode = BYTE_COMPACTION;
            textSubMode = SUBMODE_ALPHA; //Reset after latch
          }
          p += b;
        }
      }
    }
  }

  return [NSString stringWithString:sb];
}

/**
 * Encode parts of the message using Text Compaction as described in ISO/IEC 15438:2001(E),
 * chapter 4.4.2.
 */
+ (int)encodeText:(NSString*)msg startpos:(int)startpos count:(int)count buffer:(NSMutableString*)sb initialSubmode:(int)initialSubmode {
  NSMutableString* tmp = [NSMutableString stringWithCapacity:count];
  int submode = initialSubmode;
  int idx = 0;
  while (true) {
    char ch = [msg characterAtIndex:startpos + idx];
    switch (submode) {
      case SUBMODE_ALPHA:
        if ([self isAlphaUpper:ch]) {
          if (ch == ' ') {
            [tmp appendFormat:@"%c", (char) 26]; //space
          } else {
            [tmp appendFormat:@"%c", (char) (ch - 65)];
          }
        } else {
          if ([self isAlphaLower:ch]) {
            submode = SUBMODE_LOWER;
            [tmp appendFormat:@"%c", (char) 27]; //ll
            continue;
          } else if ([self isMixed:ch]) {
            submode = SUBMODE_MIXED;
            [tmp appendFormat:@"%c", (char) 28]; //ml
            continue;
          } else {
            [tmp appendFormat:@"%c", (char) 29]; //ps
            [tmp appendFormat:@"%c", (char) PUNCTUATION[ch]];
            break;
          }
        }
        break;
      case SUBMODE_LOWER:
        if ([self isAlphaLower:ch]) {
          if (ch == ' ') {
            [tmp appendFormat:@"%c", (char) 26]; //space
          } else {
            [tmp appendFormat:@"%c", (char) (ch - 97)];
          }
        } else {
          if ([self isAlphaUpper:ch]) {
            [tmp appendFormat:@"%c", (char) 27]; //as
            [tmp appendFormat:@"%c", (char) (ch - 65)];
            //space cannot happen here, it is also in "Lower"
            break;
          } else if ([self isMixed:ch]) {
            submode = SUBMODE_MIXED;
            [tmp appendFormat:@"%c", (char) 28]; //ml
            continue;
          } else {
            [tmp appendFormat:@"%c", (char) 29]; //ps
            [tmp appendFormat:@"%c", (char) PUNCTUATION[ch]];
            break;
          }
        }
        break;
      case SUBMODE_MIXED:
        if ([self isMixed:ch]) {
          [tmp appendFormat:@"%C", MIXED_TABLE[ch]]; //as
        } else {
          if ([self isAlphaUpper:ch]) {
            submode = SUBMODE_ALPHA;
            [tmp appendFormat:@"%c", (char) 28]; //al
            continue;
          } else if ([self isAlphaLower:ch]) {
            submode = SUBMODE_LOWER;
            [tmp appendFormat:@"%c", (char) 27]; //ll
            continue;
          } else {
            if (startpos + idx + 1 < count) {
              char next = [msg characterAtIndex:startpos + idx + 1];
              if ([self isPunctuation:next]) {
                submode = SUBMODE_PUNCTUATION;
                [tmp appendFormat:@"%c", (char) 25]; //pl
                continue;
              }
            }
            [tmp appendFormat:@"%c", (char) 29]; //ps
            [tmp appendFormat:@"%c", (char) PUNCTUATION[ch]];
          }
        }
        break;
      default: //SUBMODE_PUNCTUATION
        if ([self isPunctuation:ch]) {
          [tmp appendFormat:@"%c", (char) PUNCTUATION[ch]];
        } else {
          submode = SUBMODE_ALPHA;
          [tmp appendFormat:@"%c", (char) 29]; //al
          continue;
        }
    }
    idx++;
    if (idx >= count) {
      break;
    }
  }
  unichar h = 0;
  int len = tmp.length;
  for (int i = 0; i < len; i++) {
    BOOL odd = (i % 2) != 0;
    if (odd) {
      h = (unichar) ((h * 30) + [tmp characterAtIndex:i]);
      [sb appendFormat:@"%C", h];
    } else {
      h = [tmp characterAtIndex:i];
    }
  }
  if ((len % 2) != 0) {
    [sb appendFormat:@"%C", (unichar) ((h * 30) + 29)]; //ps
  }
  return submode;
}

/**
 * Encode parts of the message using Byte Compaction as described in ISO/IEC 15438:2001(E),
 * chapter 4.4.3. The Unicode characters will be converted to binary using the cp437
 * codepage.
 */
+ (void)encodeBinary:(unsigned char*)bytes startpos:(int)startpos count:(int)count startmode:(int)startmode buffer:(NSMutableString*)sb {
  if (count == 1 && startmode == TEXT_COMPACTION) {
    [sb appendFormat:@"%c", (char) SHIFT_TO_BYTE];
  } else {
    BOOL sixpack = (count % 6) == 0;
    if (sixpack) {
      [sb appendFormat:@"%c", (char) LATCH_TO_BYTE];
    } else {
      [sb appendFormat:@"%c", (char) LATCH_TO_BYTE_PADDED];
    }
  }

  const int charsLen = 5;
  char chars[charsLen] = {0};
  int idx = startpos;
  while ((startpos + count - idx) >= 6) {
    long t = 0;
    for (int i = 0; i < 6; i++) {
      t <<= 8;
      t += bytes[idx + i] & 0xff;
    }
    for (int i = 0; i < 5; i++) {
      chars[i] = (char) (t % 900);
      t /= 900;
    }
    for (int i = charsLen - 1; i >= 0; i--) {
      [sb appendFormat:@"%c", chars[i]];
    }
    idx += 6;
  }
  //Encode rest (remaining n<5 bytes if any)
  for (int i = idx; i < startpos + count; i++) {
    int ch = bytes[i] & 0xff;
    [sb appendFormat:@"%c", ch];
  }
}

// TODO either this needs to reimplement BigInteger's functionality to properly handle very
// large numeric strings, even in Java ME, or, we give up Java ME and use the version above
// with BigInteger

+ (void)encodeNumeric:(NSString*)msg startpos:(int)startpos count:(int)count buffer:(NSMutableString*)sb {
  int idx = 0;
  NSMutableString* tmp = [NSMutableString stringWithCapacity:count / 3 + 1];
  while (idx < count - 1) {
    [tmp setString:@""];
    int len = MIN(44, count - idx);
    NSString* part = [@"1" stringByAppendingString:[msg substringWithRange:NSMakeRange(startpos + idx, len)]];
    long long bigint = [part longLongValue];
    do {
      long c = bigint % 900;
      [tmp appendFormat:@"%c", (char) c];
      bigint /= 900;
    } while (bigint != 0);

    //Reverse temporary string
    for (int i = tmp.length - 1; i >= 0; i--) {
      [tmp appendFormat:@"%c", [tmp characterAtIndex:i]];
    }
    idx += len;
  }
}

+ (BOOL)isDigit:(char)ch {
  return ch >= '0' && ch <= '9';
}

+ (BOOL)isAlphaUpper:(char)ch {
  return ch == ' ' || (ch >= 'A' && ch <= 'Z');
}

+ (BOOL)isAlphaLower:(char)ch {
  return ch == ' ' || (ch >= 'a' && ch <= 'z');
}

+ (BOOL)isMixed:(char)ch {
  return MIXED_TABLE[ch] != -1;
}

+ (BOOL)isPunctuation:(char)ch {
  return PUNCTUATION[ch] != -1;
}

+ (BOOL)isText:(char)ch {
  return ch == '\t' || ch == '\n' || ch == '\r' || (ch >= 32 && ch <= 126);
}

/**
 * Determines the number of consecutive characters that are encodable using numeric compaction.
 */
+ (int)determineConsecutiveDigitCount:(NSString*)msg startpos:(int)startpos {
  int count = 0;
  int len = msg.length;
  int idx = startpos;
  if (idx < len) {
    char ch = [msg characterAtIndex:idx];
    while ([self isDigit:ch] && idx < len) {
      count++;
      idx++;
      if (idx < len) {
        ch = [msg characterAtIndex:idx];
      }
    }
  }
  return count;
}

/**
 * Determines the number of consecutive characters that are encodable using text compaction.
 *
 * @param msg      the message
 * @param startpos the start position within the message
 * @return the requested character count
 */
+ (int)determineConsecutiveTextCount:(NSString*)msg startpos:(int)startpos {
  int len = msg.length;
  int idx = startpos;
  while (idx < len) {
    char ch = [msg characterAtIndex:idx];
    int numericCount = 0;
    while (numericCount < 13 && [self isDigit:ch] && idx < len) {
      numericCount++;
      idx++;
      if (idx < len) {
        ch = [msg characterAtIndex:idx];
      }
    }
    if (numericCount >= 13) {
      return idx - startpos - numericCount;
    }
    if (numericCount > 0) {
      //Heuristic: All text-encodable chars or digits are binary encodable
      continue;
    }
    ch = [msg characterAtIndex:idx];

    //Check if character is encodable
    if (![self isText:ch]) {
      break;
    }
    idx++;
  }
  return idx - startpos;
}

/**
 * Determines the number of consecutive characters that are encodable using binary compaction.
 */
+ (int)determineConsecutiveBinaryCount:(NSString*)msg bytes:(unsigned char*)bytes startpos:(int)startpos error:(NSError**)error {
  int len = msg.length;
  int idx = startpos;
  while (idx < len) {
    char ch = [msg characterAtIndex:idx];
    int numericCount = 0;

    while (numericCount < 13 && [self isDigit:ch]) {
      numericCount++;
      //textCount++;
      int i = idx + numericCount;
      if (i >= len) {
        break;
      }
      ch = [msg characterAtIndex:i];
    }
    if (numericCount >= 13) {
      return idx - startpos;
    }
    int textCount = 0;
    while (textCount < 5 && [self isText:ch]) {
      textCount++;
      int i = idx + textCount;
      if (i >= len) {
        break;
      }
      ch = [msg characterAtIndex:i];
    }
    if (textCount >= 5) {
      return idx - startpos;
    }
    ch = [msg characterAtIndex:idx];

    //Check if character is encodable
    //Sun returns a ASCII 63 (?) for a character that cannot be mapped. Let's hope all
    //other VMs do the same
    if (bytes[idx] == 63 && ch != '?') {
      NSDictionary* userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Non-encodable character detected: %c (Unicode: %C)", ch, (int)ch]
                                                           forKey:NSLocalizedDescriptionKey];

      if (error) *error = [[[NSError alloc] initWithDomain:ZXErrorDomain code:ZXWriterError userInfo:userInfo] autorelease];
      return -1;
    }
    idx++;
  }
  return idx - startpos;
}

@end