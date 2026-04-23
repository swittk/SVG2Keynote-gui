#import <Foundation/Foundation.h>

@interface CPP_Wrapper : NSObject

- (NSData *)generateClipboardForTSPNativeData:(NSString *)svgContents;
- (NSData *)generateClipboardMetadata;
- (NSData *)generateClipboardMetadataWithDocumentUUIDString:(NSString *)documentUUIDString;
- (NSData *)generateClipboardMetadataWithDocumentUUIDString:(NSString *)documentUUIDString compatibilityProfile:(NSDictionary<NSString *, id> *)compatibilityProfile;
- (NSData *)generateClipboardDescriptionForDrawableCount:(NSInteger)drawableCount;
- (NSInteger)drawableCountForClipboardData:(NSData *)clipboardData;
- (NSDictionary<NSString *, id> *)compatibilityProfileFromClipboardMetadataData:(NSData *)metadataData;
- (NSString *)svgStringFromClipboardData:(NSData *)clipboardData;

@end
