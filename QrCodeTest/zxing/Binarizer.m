#import "Binarizer.h"

@implementation Binarizer

@synthesize luminanceSource;
@synthesize blackMatrix;

- (id) initWithSource:(LuminanceSource *)source {
  if (self = [super init]) {
    if (source == nil) {
      @throw [[[IllegalArgumentException alloc] init:@"Source must be non-null."] autorelease];
    }
    source = source;
  }
  return self;
}


/**
 * Converts one row of luminance data to 1 bit data. May actually do the conversion, or return
 * cached data. Callers should assume this method is expensive and call it as seldom as possible.
 * This method is intended for decoding 1D barcodes and may choose to apply sharpening.
 * For callers which only examine one row of pixels at a time, the same BitArray should be reused
 * and passed in with each call for performance. However it is legal to keep more than one row
 * at a time if needed.
 * 
 * @param y The row to fetch, 0 <= y < bitmap height.
 * @param row An optional preallocated array. If null or too small, it will be ignored.
 * If used, the Binarizer will call BitArray.clear(). Always use the returned object.
 * @return The array of bits for this row (true means black).
 */
- (BitArray *) getBlackRow:(int)y row:(BitArray *)row {
}


/**
 * Converts a 2D array of luminance data to 1 bit data. As above, assume this method is expensive
 * and do not call it repeatedly. This method is intended for decoding 2D barcodes and may or
 * may not apply sharpening. Therefore, a row from this matrix may not be identical to one
 * fetched using getBlackRow(), so don't mix and match between them.
 * 
 * @return The 2D array of bits for the image (true means black).
 */
- (BitMatrix *) blackMatrix {
}


/**
 * Creates a new object with the same type as this Binarizer implementation, but with pristine
 * state. This is needed because Binarizer implementations may be stateful, e.g. keeping a cache
 * of 1 bit data. See Effective Java for why we can't use Java's clone() method.
 * 
 * @param source The LuminanceSource this Binarizer will operate on.
 * @return A new concrete Binarizer implementation object.
 */
- (Binarizer *) createBinarizer:(LuminanceSource *)source {
}

- (void) dealloc {
  [source release];
  [super dealloc];
}

@end
