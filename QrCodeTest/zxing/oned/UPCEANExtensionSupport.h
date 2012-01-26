#import "NSMutableDictionary.h"
#import "BarcodeFormat.h"
#import "NotFoundException.h"
#import "Result.h"
#import "ResultMetadataType.h"
#import "ResultPoint.h"
#import "BitArray.h"

@interface UPCEANExtensionSupport : NSObject {
  NSArray * decodeMiddleCounters;
  StringBuffer * decodeRowStringBuffer;
}

- (void) init;
- (Result *) decodeRow:(int)rowNumber row:(BitArray *)row rowOffset:(int)rowOffset;
- (int) decodeMiddle:(BitArray *)row startRange:(NSArray *)startRange resultString:(StringBuffer *)resultString;
@end
