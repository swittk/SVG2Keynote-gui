#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>

#import "../KeynoteSVGUI/wrapper.h"

static NSString *SHA256StringForData(NSData *data) {
    if (data.length == 0) {
        return @"";
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

    NSMutableString *output = [NSMutableString stringWithCapacity:(NSUInteger)CC_SHA256_DIGEST_LENGTH * 2];
    for (NSInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; ++index) {
        [output appendFormat:@"%02x", digest[index]];
    }
    return output;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: generate_payload_probe <svg-path> [output-directory]\n");
            return 1;
        }

        NSString *svgPath = [NSString stringWithUTF8String:argv[1]];
        NSString *svg = [NSString stringWithContentsOfFile:svgPath encoding:NSUTF8StringEncoding error:nil];
        if (svg.length == 0) {
            fprintf(stderr, "failed to read SVG: %s\n", svgPath.UTF8String ?: "");
            return 2;
        }

        CPP_Wrapper *wrapper = [[CPP_Wrapper alloc] init];
        NSData *nativeData = [wrapper generateClipboardForTSPNativeData:svg];
        NSInteger drawableCount = [wrapper drawableCountForClipboardData:nativeData];
        NSData *metadata = [wrapper generateClipboardMetadataWithDocumentUUIDString:@"11111111-2222-3333-4444-555555555555" compatibilityProfile:nil];
        NSData *descriptionData = [wrapper generateClipboardDescriptionForDrawableCount:drawableCount];

        printf("native\tlen=%lu\tsha256=%s\n",
               (unsigned long)nativeData.length,
               SHA256StringForData(nativeData).UTF8String ?: "");
        printf("metadata\tlen=%lu\tsha256=%s\n",
               (unsigned long)metadata.length,
               SHA256StringForData(metadata).UTF8String ?: "");
        printf("description\tlen=%lu\tsha256=%s\n",
               (unsigned long)descriptionData.length,
               SHA256StringForData(descriptionData).UTF8String ?: "");
        printf("drawableCount=%ld\n", (long)drawableCount);

        if (argc > 2) {
            NSString *outputDirectory = [NSString stringWithUTF8String:argv[2]];
            [[NSFileManager defaultManager] createDirectoryAtPath:outputDirectory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
            [nativeData writeToFile:[outputDirectory stringByAppendingPathComponent:@"com.apple.iWork.TSPNativeData"] atomically:YES];
            [metadata writeToFile:[outputDirectory stringByAppendingPathComponent:@"com.apple.iWork.TSPNativeMetadata"] atomically:YES];
            [descriptionData writeToFile:[outputDirectory stringByAppendingPathComponent:@"com.apple.iWork.TSPDescription"] atomically:YES];
        }
    }
    return 0;
}
