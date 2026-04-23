#import <Foundation/Foundation.h>

@interface CPP_Wrapper : NSObject

- (NSData *)generateClipboardForTSPNativeData:(NSString *)svgContents;
- (NSData *)generateClipboardMetadata;
- (NSData *)generateClipboardMetadataWithDocumentUUIDString:(NSString *)documentUUIDString;
- (NSData *)generateClipboardDescriptionForDrawableCount:(NSInteger)drawableCount;
- (NSInteger)drawableCountForClipboardData:(NSData *)clipboardData;

@end
