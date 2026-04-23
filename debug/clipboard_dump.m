#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>

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
        NSString *outputDirectory = nil;
        if (argc > 1) {
            outputDirectory = [NSString stringWithUTF8String:argv[1]];
            [[NSFileManager defaultManager] createDirectoryAtPath:outputDirectory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
        }

        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        NSArray<NSPasteboardType> *types = pasteboard.types ?: @[];

        printf("changeCount=%ld\n", (long)pasteboard.changeCount);
        printf("types=%ld\n", (long)types.count);

        for (NSPasteboardType type in types) {
            NSData *data = [pasteboard dataForType:type];
            NSString *sha = SHA256StringForData(data);
            printf("%s\tlen=%lu\tsha256=%s\n",
                   type.UTF8String ?: "",
                   (unsigned long)data.length,
                   sha.UTF8String ?: "");

            if (outputDirectory.length > 0 && data.length > 0) {
                NSCharacterSet *invalidSet = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"] invertedSet];
                NSString *fileName = [[type componentsSeparatedByCharactersInSet:invalidSet] componentsJoinedByString:@"_"];
                if (fileName.length == 0) {
                    fileName = @"pasteboard_item";
                }
                NSString *path = [outputDirectory stringByAppendingPathComponent:fileName];
                [data writeToFile:path atomically:YES];
            }
        }
    }
    return 0;
}
