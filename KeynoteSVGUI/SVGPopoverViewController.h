@import Cocoa;
@import WebKit;

@interface SVGPopoverViewController : NSViewController <WKNavigationDelegate>

+ (NSArray<NSPasteboardType> *)supportedSVGPasteboardTypes;
- (BOOL)canImportSVGFromPasteboard:(NSPasteboard *)pasteboard;
- (BOOL)importSVGFromPasteboard:(NSPasteboard *)pasteboard;

@end
