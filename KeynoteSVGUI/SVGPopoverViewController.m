@import Cocoa;
@import WebKit;

#import "AppDelegate.h"
#import "SVGPopoverViewController.h"
#import "wrapper.h"

static NSString *const kCompatibilityProfileDefaultsKey = @"CompatibilityProfile";
static NSPasteboardType const kSVGImagePboardType = @"public.svg-image";
static NSPasteboardType const kSVGDocumentPboardType = @"public.svg";

typedef struct {
    NSInteger topLevelDrawableCount;
    NSInteger drawableInfoKindsCount;
    NSUInteger elementKindsMask;
    NSInteger objectCount;
    NSInteger maxInlineNestingDepth;
} ClipboardDescriptionSummary;

static void AccumulateClipboardDescriptionDrawable(id drawableDescription,
                                                  NSMutableSet<NSString *> *topLevelClasses,
                                                  NSUInteger *elementKindsMask,
                                                  NSInteger *maxInlineNestingDepth,
                                                  BOOL isTopLevel) {
    if (![drawableDescription isKindOfClass:[NSDictionary class]]) {
        return;
    }

    NSDictionary *drawableDictionary = (NSDictionary *)drawableDescription;
    if (isTopLevel) {
        NSString *className = drawableDictionary[@"class"];
        if ([className isKindOfClass:[NSString class]] && className.length > 0) {
            [topLevelClasses addObject:className];
        }
    }

    NSNumber *elementKind = drawableDictionary[@"elementKind"];
    if ([elementKind isKindOfClass:[NSNumber class]]) {
        NSInteger kindValue = elementKind.integerValue;
        if (kindValue > 0 && kindValue <= (NSInteger)(sizeof(NSUInteger) * 8)) {
            *elementKindsMask |= ((NSUInteger)1 << (NSUInteger)(kindValue - 1));
        }
    }

    NSNumber *inlineDepth = drawableDictionary[@"maxInlineNestingDepth"];
    if ([inlineDepth isKindOfClass:[NSNumber class]]) {
        *maxInlineNestingDepth = MAX(*maxInlineNestingDepth, inlineDepth.integerValue);
    }

    NSArray *groupChildren = drawableDictionary[@"groupChildren"];
    if (![groupChildren isKindOfClass:[NSArray class]]) {
        return;
    }

    for (id childDescription in groupChildren) {
        AccumulateClipboardDescriptionDrawable(childDescription, topLevelClasses, elementKindsMask, maxInlineNestingDepth, NO);
    }
}

static ClipboardDescriptionSummary ClipboardDescriptionSummaryFromData(NSData *clipboardDescriptionData, NSInteger fallbackDrawableCount) {
    ClipboardDescriptionSummary summary;
    summary.topLevelDrawableCount = MAX(fallbackDrawableCount, 1);
    summary.drawableInfoKindsCount = 1;
    summary.elementKindsMask = 2;
    summary.objectCount = 2;
    summary.maxInlineNestingDepth = 1;

    if (clipboardDescriptionData.length == 0) {
        return summary;
    }

    NSError *error = nil;
    id propertyList = [NSPropertyListSerialization propertyListWithData:clipboardDescriptionData
                                                                options:NSPropertyListImmutable
                                                                 format:NULL
                                                                  error:&error];
    if (error != nil || ![propertyList isKindOfClass:[NSDictionary class]]) {
        return summary;
    }

    NSDictionary *clipboardDescription = (NSDictionary *)propertyList;
    summary.objectCount = MAX((NSInteger)clipboardDescription.count, 1);

    NSArray *drawables = clipboardDescription[@"drawables"];
    if (![drawables isKindOfClass:[NSArray class]] || drawables.count == 0) {
        return summary;
    }

    summary.topLevelDrawableCount = MAX((NSInteger)drawables.count, 1);
    NSMutableSet<NSString *> *topLevelClasses = [NSMutableSet set];
    NSUInteger elementKindsMask = 0;
    NSInteger maxInlineNestingDepth = 1;
    for (id drawableDescription in drawables) {
        AccumulateClipboardDescriptionDrawable(drawableDescription, topLevelClasses, &elementKindsMask, &maxInlineNestingDepth, YES);
    }

    summary.drawableInfoKindsCount = MAX((NSInteger)topLevelClasses.count, 1);
    summary.elementKindsMask = elementKindsMask > 0 ? elementKindsMask : summary.elementKindsMask;
    summary.maxInlineNestingDepth = MAX(maxInlineNestingDepth, 1);
    return summary;
}

@interface SVGPopoverViewController ()
@property (nonatomic, strong) WKWebView *previewView;
@property (nonatomic, strong) NSTextField *previewPlaceholderLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *openButton;
@property (nonatomic, strong) NSButton *pasteSVGButton;
@property (nonatomic, strong) NSButton *syncButton;
@property (nonatomic, strong) NSButton *saveClipboardButton;
@property (nonatomic, strong) NSButton *clipboardButton;
@property (nonatomic, strong) NSButton *quitButton;
@property (nonatomic, copy) NSString *currentSVGString;
@property (nonatomic, copy) NSString *currentDocumentName;
@property (nonatomic, strong) NSURL *currentFileURL;
@property (nonatomic, assign) BOOL previewReady;
@end

@implementation SVGPopoverViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 400.0, 300.0)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildInterface];
    [self loadPlaceholder];
}

- (void)configureSmallButton:(NSButton *)button {
    button.controlSize = NSControlSizeSmall;
    button.bezelStyle = NSBezelStyleRounded;
}

- (void)buildInterface {
    const CGFloat width = NSWidth(self.view.bounds);
    const CGFloat height = NSHeight(self.view.bounds);
    const CGFloat padding = 10.0;
    const CGFloat buttonHeight = 24.0;
    const CGFloat rowSpacing = 6.0;
    const CGFloat statusHeight = 28.0;
    const CGFloat row2Y = 10.0;
    const CGFloat row1Y = row2Y + buttonHeight + rowSpacing;
    const CGFloat statusY = row1Y + buttonHeight + 8.0;
    const CGFloat previewY = statusY + statusHeight + 8.0;
    const CGFloat previewWidth = width - (padding * 2.0);
    const CGFloat previewHeight = height - padding - previewY;

    NSView *previewContainer = [[NSView alloc] initWithFrame:NSMakeRect(padding, previewY, previewWidth, previewHeight)];
    previewContainer.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    previewContainer.wantsLayer = YES;
    previewContainer.layer.backgroundColor = NSColor.clearColor.CGColor;
    previewContainer.layer.borderColor = [NSColor colorWithCalibratedWhite:0.78 alpha:1.0].CGColor;
    previewContainer.layer.borderWidth = 1.0;
    previewContainer.layer.cornerRadius = 6.0;
    previewContainer.layer.masksToBounds = YES;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    self.previewView = [[WKWebView alloc] initWithFrame:previewContainer.bounds configuration:configuration];
    self.previewView.navigationDelegate = self;
    self.previewView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.previewView setValue:@NO forKey:@"drawsBackground"];

    self.previewPlaceholderLabel = [[NSTextField alloc] initWithFrame:previewContainer.bounds];
    self.previewPlaceholderLabel.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.previewPlaceholderLabel.bezeled = NO;
    self.previewPlaceholderLabel.drawsBackground = NO;
    self.previewPlaceholderLabel.editable = NO;
    self.previewPlaceholderLabel.selectable = NO;
    self.previewPlaceholderLabel.alignment = NSTextAlignmentCenter;
    self.previewPlaceholderLabel.font = [NSFont systemFontOfSize:12.0];
    self.previewPlaceholderLabel.textColor = [NSColor colorWithCalibratedWhite:0.42 alpha:1.0];
    self.previewPlaceholderLabel.stringValue = @"Open or paste SVG.";
    self.previewPlaceholderLabel.usesSingleLineMode = NO;
    self.previewPlaceholderLabel.lineBreakMode = NSLineBreakByWordWrapping;

    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, statusY, previewWidth, statusHeight)];
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    self.statusLabel.bezeled = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.editable = NO;
    self.statusLabel.font = [NSFont systemFontOfSize:11.0];
    self.statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.statusLabel.selectable = NO;
    self.statusLabel.stringValue = @"";
    self.statusLabel.usesSingleLineMode = NO;

    self.openButton = [NSButton buttonWithTitle:@"Open SVG" target:self action:@selector(openSVG:)];
    [self configureSmallButton:self.openButton];
    self.openButton.toolTip = @"Open SVG File";
    self.openButton.frame = NSMakeRect(padding, row1Y, 82.0, buttonHeight);
    self.openButton.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;

    self.pasteSVGButton = [NSButton buttonWithTitle:@"Paste SVG" target:self action:@selector(pasteSVGFromClipboard:)];
    [self configureSmallButton:self.pasteSVGButton];
    self.pasteSVGButton.toolTip = @"Load SVG markup from the clipboard";
    self.pasteSVGButton.frame = NSMakeRect(NSMaxX(self.openButton.frame) + 8.0, row1Y, 82.0, buttonHeight);
    self.pasteSVGButton.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;

    self.syncButton = [NSButton buttonWithTitle:@"Resync" target:self action:@selector(resyncCompatibility:)];
    [self configureSmallButton:self.syncButton];
    self.syncButton.toolTip = @"Resync compatibility from a real Keynote clipboard item";
    self.syncButton.frame = NSMakeRect(padding, row2Y, 72.0, buttonHeight);
    self.syncButton.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;

    self.saveClipboardButton = [NSButton buttonWithTitle:@"Save..." target:self action:@selector(saveClipboard:)];
    [self configureSmallButton:self.saveClipboardButton];
    self.saveClipboardButton.toolTip = @"Save vector or image data from the clipboard";
    self.saveClipboardButton.frame = NSMakeRect(NSMaxX(self.syncButton.frame) + 8.0, row2Y, 64.0, buttonHeight);
    self.saveClipboardButton.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;

    self.quitButton = [NSButton buttonWithTitle:@"Quit" target:self action:@selector(quitApp:)];
    [self configureSmallButton:self.quitButton];
    self.quitButton.frame = NSMakeRect(NSMaxX(self.saveClipboardButton.frame) + 8.0, row2Y, 50.0, buttonHeight);
    self.quitButton.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;

    self.clipboardButton = [NSButton buttonWithTitle:@"Copy Shapes" target:self action:@selector(copyToClipboard:)];
    self.clipboardButton.enabled = NO;
    [self configureSmallButton:self.clipboardButton];
    self.clipboardButton.toolTip = @"Copy editable Keynote shapes to the clipboard";
    self.clipboardButton.frame = NSMakeRect(width - padding - 106.0, row1Y, 106.0, buttonHeight);
    self.clipboardButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;

    [previewContainer addSubview:self.previewView];
    [previewContainer addSubview:self.previewPlaceholderLabel];
    [self.view addSubview:previewContainer];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.openButton];
    [self.view addSubview:self.pasteSVGButton];
    [self.view addSubview:self.syncButton];
    [self.view addSubview:self.saveClipboardButton];
    [self.view addSubview:self.quitButton];
    [self.view addSubview:self.clipboardButton];
}

- (void)loadPlaceholder {
    self.currentDocumentName = nil;
    self.previewReady = NO;
    self.clipboardButton.enabled = NO;
    self.previewPlaceholderLabel.hidden = NO;
    self.previewPlaceholderLabel.stringValue = @"Open or paste SVG.";
    NSString *status = @"Open or paste SVG, then copy editable Keynote shapes.";
    NSDictionary<NSString *, id> *compatibilityProfile = [self savedCompatibilityProfile];
    if (compatibilityProfile.count > 0) {
        status = [status stringByAppendingFormat:@" Active compatibility: %@.", [self compatibilitySummaryForProfile:compatibilityProfile]];
    }
    [self updateStatus:status];
    [self.previewView loadHTMLString:@"<!DOCTYPE html><html><body style=\"margin:0; background:transparent;\"></body></html>" baseURL:nil];
}

- (void)activateForForegroundInteraction {
    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)looksLikeSVGString:(NSString *)candidateString {
    if (![candidateString isKindOfClass:[NSString class]] || candidateString.length == 0) {
        return NO;
    }

    NSRange svgRange = [candidateString rangeOfString:@"<svg" options:NSCaseInsensitiveSearch];
    return svgRange.location != NSNotFound;
}

- (NSString *)SVGStringFromFileURL:(NSURL *)fileURL error:(NSError **)error {
    NSStringEncoding usedEncoding = 0;
    NSString *svgString = [NSString stringWithContentsOfURL:fileURL usedEncoding:&usedEncoding error:error];
    if (svgString != nil) {
        return svgString;
    }

    NSData *data = [NSData dataWithContentsOfURL:fileURL options:0 error:error];
    if (data == nil) {
        return nil;
    }

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)loadSVGString:(NSString *)svgString fromFileURL:(NSURL *)fileURL displayName:(NSString *)displayName {
    self.currentSVGString = svgString;
    self.currentFileURL = fileURL;
    self.currentDocumentName = displayName.length > 0 ? displayName : (fileURL.lastPathComponent ?: @"SVG");
    self.previewReady = NO;
    self.clipboardButton.enabled = NO;
    self.previewPlaceholderLabel.hidden = NO;
    self.previewPlaceholderLabel.stringValue = @"Loading preview…";

    [self updateStatus:[NSString stringWithFormat:@"Loading %@…", self.currentDocumentName]];
    if (fileURL.isFileURL) {
        NSURL *readAccessURL = fileURL.URLByDeletingLastPathComponent ?: fileURL;
        [self.previewView loadFileURL:fileURL allowingReadAccessToURL:readAccessURL];
        return;
    }

    NSData *svgData = [svgString dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *baseURL = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    [self.previewView loadData:svgData MIMEType:@"image/svg+xml" characterEncodingName:@"utf-8" baseURL:baseURL];
}

- (NSString *)SVGStringFromPasteboard:(NSPasteboard *)pasteboard {
    for (NSPasteboardType type in @[ kSVGImagePboardType, kSVGDocumentPboardType, NSPasteboardTypeString ]) {
        NSString *stringValue = [pasteboard stringForType:type];
        if ([self looksLikeSVGString:stringValue]) {
            return stringValue;
        }

        NSData *dataValue = [pasteboard dataForType:type];
        if (dataValue.length == 0) {
            continue;
        }

        NSString *dataString = [[NSString alloc] initWithData:dataValue encoding:NSUTF8StringEncoding];
        if ([self looksLikeSVGString:dataString]) {
            return dataString;
        }
    }

    return nil;
}

- (BOOL)importSVGFromPasteboard:(NSPasteboard *)pasteboard {
    NSString *svgString = [self SVGStringFromPasteboard:pasteboard];
    if (svgString.length == 0) {
        [self updateStatus:@"Clipboard does not currently contain SVG markup."];
        return NO;
    }

    [self loadSVGString:svgString fromFileURL:nil displayName:@"Clipboard SVG"];
    return YES;
}

- (void)openSVG:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[ @"svg" ];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canCreateDirectories = NO;
    panel.directoryURL = self.currentFileURL.URLByDeletingLastPathComponent;

    NSInteger response = [self runModalPanelWithPopoverTemporarilyClosed:panel];
    if (response != NSModalResponseOK) {
        return;
    }

    NSURL *selectedURL = panel.URL;
    NSError *error = nil;
    NSString *svgString = [self SVGStringFromFileURL:selectedURL error:&error];
    if (svgString == nil) {
        [self updateStatus:[NSString stringWithFormat:@"Failed to read %@.", selectedURL.lastPathComponent ?: @"the selected file"]];
        return;
    }

    [self loadSVGString:svgString fromFileURL:selectedURL displayName:selectedURL.lastPathComponent];
}

- (void)pasteSVGFromClipboard:(id)sender {
    [self importSVGFromPasteboard:[NSPasteboard generalPasteboard]];
}

- (NSInteger)runModalPanelWithPopoverTemporarilyClosed:(NSSavePanel *)panel {
    [self activateForForegroundInteraction];

    AppDelegate *appDelegate = (AppDelegate *)NSApp.delegate;
    const BOOL shouldRestorePopover = [appDelegate isPopoverShown];
    if (shouldRestorePopover) {
        [appDelegate closePopover];
    }

    NSInteger response = [panel runModal];
    [self activateForForegroundInteraction];
    if (shouldRestorePopover) {
        [appDelegate showPopoverFromStatusItem];
    }

    return response;
}

- (void)copyToClipboard:(id)sender {
    if (!self.previewReady || self.currentSVGString.length == 0) {
        [self updateStatus:@"Wait for the preview to finish loading before copying."];
        return;
    }

    self.clipboardButton.enabled = NO;
    [self updateStatus:@"Building native Keynote clipboard data…"];

    CPP_Wrapper *wrapper = [[CPP_Wrapper alloc] init];
    NSString *documentUUIDString = NSUUID.UUID.UUIDString;
    NSData *clipboardData = [wrapper generateClipboardForTSPNativeData:self.currentSVGString];
    NSInteger drawableCount = [wrapper drawableCountForClipboardData:clipboardData];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSDictionary<NSString *, id> *compatibilityProfile = [self activeCompatibilityProfileFromPasteboard:pasteboard wrapper:wrapper];
    NSData *metadata = [wrapper generateClipboardMetadataWithDocumentUUIDString:documentUUIDString compatibilityProfile:compatibilityProfile];
    NSData *clipboardDescription = [wrapper generateClipboardDescriptionForDrawableCount:drawableCount];

    if (clipboardData.length == 0 || metadata.length == 0 || clipboardDescription.length == 0) {
        self.clipboardButton.enabled = self.previewReady;
        [self updateStatus:@"Failed to generate Keynote clipboard data from the SVG."];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self capturePreviewImageDataWithCompletion:^(NSData *pngData, NSData *tiffData) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        strongSelf.clipboardButton.enabled = strongSelf.previewReady;
        [strongSelf writeKeynoteClipboardData:clipboardData
                                     metadata:metadata
                         clipboardDescription:clipboardDescription
                                drawableCount:drawableCount
                                      pngData:pngData
                                     tiffData:tiffData];

        NSString *status = @"Copied editable Keynote shapes. Paste into Keynote with Command-V.";
        if (compatibilityProfile.count > 0) {
            status = [status stringByAppendingFormat:@" Using %@ compatibility.", [strongSelf compatibilitySummaryForProfile:compatibilityProfile]];
        }
        [strongSelf updateStatus:status];
    }];
}

- (void)quitApp:(id)sender {
    [NSApp terminate:sender];
}

- (NSData *)PNGDataForImage:(NSImage *)image {
    if (image == nil) {
        return nil;
    }

    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (cgImage != NULL) {
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
        return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    }

    NSData *tiffData = [image TIFFRepresentation];
    if (tiffData.length == 0) {
        return nil;
    }

    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiffData];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

- (void)resyncCompatibility:(id)sender {
    CPP_Wrapper *wrapper = [[CPP_Wrapper alloc] init];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSDictionary<NSString *, id> *compatibilityProfile = [wrapper compatibilityProfileFromClipboardMetadataData:[pasteboard dataForType:@"com.apple.iWork.TSPNativeMetadata"]];
    if (compatibilityProfile.count == 0) {
        [self updateStatus:@"Copy a simple Keynote shape first, then click Resync Compatibility."];
        return;
    }

    [[NSUserDefaults standardUserDefaults] setObject:compatibilityProfile forKey:kCompatibilityProfileDefaultsKey];
    [self updateStatus:[NSString stringWithFormat:@"Synced compatibility to %@.", [self compatibilitySummaryForProfile:compatibilityProfile]]];
}

- (NSDictionary<NSString *, id> *)savedCompatibilityProfile {
    id compatibilityProfile = [[NSUserDefaults standardUserDefaults] objectForKey:kCompatibilityProfileDefaultsKey];
    return [compatibilityProfile isKindOfClass:[NSDictionary class]] ? compatibilityProfile : nil;
}

- (NSDictionary<NSString *, id> *)activeCompatibilityProfileFromPasteboard:(NSPasteboard *)pasteboard wrapper:(CPP_Wrapper *)wrapper {
    NSDictionary<NSString *, id> *savedCompatibilityProfile = [self savedCompatibilityProfile];
    if (savedCompatibilityProfile.count > 0) {
        return savedCompatibilityProfile;
    }

    return [wrapper compatibilityProfileFromClipboardMetadataData:[pasteboard dataForType:@"com.apple.iWork.TSPNativeMetadata"]];
}

- (NSString *)compatibilitySummaryForProfile:(NSDictionary<NSString *, id> *)compatibilityProfile {
    NSString *appName = compatibilityProfile[@"appName"];
    NSArray<NSNumber *> *version = compatibilityProfile[@"version"];
    NSString *displayName = appName;

    if ([displayName hasPrefix:@"com.apple.Keynote "]) {
        displayName = [NSString stringWithFormat:@"Keynote %@", [displayName substringFromIndex:@"com.apple.Keynote ".length]];
    }

    if ([version isKindOfClass:[NSArray class]] && version.count >= 3) {
        return [NSString stringWithFormat:@"%@ (%@.%@.%@)", displayName ?: @"Keynote", version[0], version[1], version[2]];
    }

    return displayName.length > 0 ? displayName : @"Keynote";
}

- (void)capturePreviewImageDataWithCompletion:(void (^)(NSData *pngData, NSData *tiffData))completion {
    if (completion == nil) {
        return;
    }

    [self.previewView takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *snapshotImage, NSError *error) {
        void (^finishOnMain)(NSData *, NSData *) = ^(NSData *pngData, NSData *tiffData) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(pngData, tiffData);
            });
        };

        if (snapshotImage == nil || error != nil) {
            finishOnMain(nil, nil);
            return;
        }

        finishOnMain([self PNGDataForImage:snapshotImage], snapshotImage.TIFFRepresentation);
    }];
}

- (void)saveClipboard:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    CPP_Wrapper *wrapper = [[CPP_Wrapper alloc] init];

    NSData *nativeData = [pasteboard dataForType:@"com.apple.iWork.TSPNativeData"];
    if (nativeData.length > 0) {
        NSString *svgString = [wrapper svgStringFromClipboardData:nativeData];
        if (svgString.length > 0) {
            NSSavePanel *panel = [NSSavePanel savePanel];
            panel.allowedFileTypes = @[ @"svg" ];
            panel.canCreateDirectories = YES;
            panel.directoryURL = self.currentFileURL.URLByDeletingLastPathComponent;
            panel.nameFieldStringValue = @"keynote-clipboard.svg";

            if ([self runModalPanelWithPopoverTemporarilyClosed:panel] != NSModalResponseOK) {
                return;
            }

            NSError *writeError = nil;
            if ([svgString writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
                [self updateStatus:[NSString stringWithFormat:@"Saved vector clipboard data as %@.", panel.URL.lastPathComponent ?: @"SVG"]];
            } else {
                [self updateStatus:writeError.localizedDescription ?: @"Failed to save the SVG file."];
            }
            return;
        }
    }

    if ([NSImage canInitWithPasteboard:pasteboard]) {
        NSImage *image = [[NSImage alloc] initWithPasteboard:pasteboard];
        NSData *pngData = [self PNGDataForImage:image];
        if (pngData.length > 0) {
            NSSavePanel *panel = [NSSavePanel savePanel];
            panel.allowedFileTypes = @[ @"png" ];
            panel.canCreateDirectories = YES;
            panel.directoryURL = self.currentFileURL.URLByDeletingLastPathComponent;
            panel.nameFieldStringValue = @"clipboard-image.png";

            if ([self runModalPanelWithPopoverTemporarilyClosed:panel] != NSModalResponseOK) {
                return;
            }

            NSError *writeError = nil;
            if ([pngData writeToURL:panel.URL options:NSDataWritingAtomic error:&writeError]) {
                [self updateStatus:[NSString stringWithFormat:@"Saved clipboard image as %@.", panel.URL.lastPathComponent ?: @"PNG"]];
            } else {
                [self updateStatus:writeError.localizedDescription ?: @"Failed to save the clipboard image."];
            }
            return;
        }
    }

    [self updateStatus:@"Clipboard does not contain an exportable Keynote vector shape or image."];
}

- (void)writeKeynoteClipboardData:(NSData *)clipboardData
                         metadata:(NSData *)metadata
             clipboardDescription:(NSData *)clipboardDescription
                    drawableCount:(NSInteger)drawableCount
                          pngData:(NSData *)pngData
                         tiffData:(NSData *)tiffData {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSPasteboardType nativeDataType = @"com.apple.iWork.TSPNativeData";
    NSPasteboardType metadataType = @"com.apple.iWork.TSPNativeMetadata";
    NSPasteboardType descriptionType = @"com.apple.iWork.TSPDescription";
    NSPasteboardType hasNativeDrawablesType = @"com.apple.iWork.pasteboardState.hasNativeDrawables";
    ClipboardDescriptionSummary descriptionSummary = ClipboardDescriptionSummaryFromData(clipboardDescription, drawableCount);
    NSMutableArray<NSPasteboardType> *types = [NSMutableArray arrayWithArray:@[
        nativeDataType,
        metadataType,
        descriptionType,
        hasNativeDrawablesType,
        @"com.apple.iWork.pasteboardState.hasNativeTypes",
        [NSString stringWithFormat:@"com.apple.iWork.pasteboardState.drawableInfoKinds-%ld", (long)descriptionSummary.drawableInfoKindsCount],
        [NSString stringWithFormat:@"com.apple.iWork.pasteboardState.elementKinds-%lu", (unsigned long)descriptionSummary.elementKindsMask],
        [NSString stringWithFormat:@"com.apple.iWork.pasteboardState.countOfObject-%ld", (long)descriptionSummary.objectCount],
        [NSString stringWithFormat:@"com.apple.iWork.pasteboardState.maxinlinenestingdepth-%ld", (long)descriptionSummary.maxInlineNestingDepth],
    ]];
    [types addObject:[NSString stringWithFormat:@"com.apple.iWork.pasteboardState.numberOfDrawables-%ld", (long)descriptionSummary.topLevelDrawableCount]];
    [types addObject:[NSString stringWithFormat:@"com.apple.iWork.pasteboardState.numberOfTopLevelDrawables-%ld", (long)descriptionSummary.topLevelDrawableCount]];
    if (pngData.length > 0) {
        [types addObject:NSPasteboardTypePNG];
        [types addObject:@"Apple PNG pasteboard type"];
    }
    if (tiffData.length > 0) {
        [types addObject:NSPasteboardTypeTIFF];
        [types addObject:@"NeXT TIFF v4.0 pasteboard type"];
    }

    [pasteboard declareTypes:types owner:nil];
    [pasteboard setData:clipboardData forType:nativeDataType];
    [pasteboard setData:metadata forType:metadataType];
    [pasteboard setData:clipboardDescription forType:descriptionType];
    if (pngData.length > 0) {
        [pasteboard setData:pngData forType:NSPasteboardTypePNG];
        [pasteboard setData:pngData forType:@"Apple PNG pasteboard type"];
    }
    if (tiffData.length > 0) {
        [pasteboard setData:tiffData forType:NSPasteboardTypeTIFF];
        [pasteboard setData:tiffData forType:@"NeXT TIFF v4.0 pasteboard type"];
    }

    NSData *markerData = [NSData data];
    for (NSPasteboardType type in types) {
        if ([type isEqualToString:nativeDataType] ||
            [type isEqualToString:metadataType] ||
            [type isEqualToString:descriptionType] ||
            [type isEqualToString:NSPasteboardTypePNG] ||
            [type isEqualToString:@"Apple PNG pasteboard type"] ||
            [type isEqualToString:NSPasteboardTypeTIFF] ||
            [type isEqualToString:@"NeXT TIFF v4.0 pasteboard type"]) {
            continue;
        }
        [pasteboard setData:markerData forType:type];
    }
}

- (void)updateStatus:(NSString *)statusText {
    self.statusLabel.stringValue = statusText ?: @"";
}

- (void)fitPreviewToContainerWithCompletion:(void (^)(void))completion {
    NSString *script =
    @"(() => {"
    "  try {"
    "    const root = document.documentElement;"
    "    if (!root) { return true; }"
    "    root.style.margin = '0';"
    "    root.style.width = '100%';"
    "    root.style.height = '100%';"
    "    root.style.overflow = 'hidden';"
    "    root.style.background = 'transparent';"
    "    if (document.body) {"
    "      document.body.style.margin = '0';"
    "      document.body.style.width = '100%';"
    "      document.body.style.height = '100%';"
    "      document.body.style.overflow = 'hidden';"
    "      document.body.style.background = 'transparent';"
    "    }"
    "    if (root.tagName && root.tagName.toLowerCase() === 'svg') {"
    "      root.style.display = 'block';"
    "      root.style.maxWidth = '100%';"
    "      root.style.maxHeight = '100%';"
    "      root.setAttribute('width', '100%');"
    "      root.setAttribute('height', '100%');"
    "      root.setAttribute('preserveAspectRatio', 'xMidYMid meet');"
    "      if (typeof root.getBBox === 'function') {"
    "        const box = root.getBBox();"
    "        if (box && isFinite(box.x) && isFinite(box.y) && isFinite(box.width) && isFinite(box.height) && box.width > 0 && box.height > 0) {"
    "          const padX = Math.max(box.width * 0.05, 1);"
    "          const padY = Math.max(box.height * 0.05, 1);"
    "          root.setAttribute('viewBox', `${box.x - padX} ${box.y - padY} ${box.width + padX * 2} ${box.height + padY * 2}`);"
    "        }"
    "      }"
    "    }"
    "  } catch (error) {"
    "  }"
    "  return true;"
    "})()";

    [self.previewView evaluateJavaScript:script completionHandler:^(__unused id result, __unused NSError *error) {
        if (completion != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    }];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    __weak typeof(self) weakSelf = self;
    [self fitPreviewToContainerWithCompletion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        strongSelf.previewPlaceholderLabel.hidden = YES;
        strongSelf.previewReady = YES;
        strongSelf.clipboardButton.enabled = (strongSelf.currentSVGString.length > 0);
        NSString *fileName = strongSelf.currentDocumentName ?: strongSelf.currentFileURL.lastPathComponent ?: @"SVG";
        NSString *status = [NSString stringWithFormat:@"%@ loaded. Copy shapes and paste into Keynote.", fileName];
        NSDictionary<NSString *, id> *compatibilityProfile = [strongSelf savedCompatibilityProfile];
        if (compatibilityProfile.count > 0) {
            status = [status stringByAppendingFormat:@" Active compatibility: %@.", [strongSelf compatibilitySummaryForProfile:compatibilityProfile]];
        }
        [strongSelf updateStatus:status];
    }];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.previewPlaceholderLabel.hidden = NO;
    self.previewPlaceholderLabel.stringValue = @"Preview failed.";
    self.previewReady = NO;
    self.clipboardButton.enabled = NO;
    [self updateStatus:error.localizedDescription ?: @"The SVG preview failed to load."];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.previewPlaceholderLabel.hidden = NO;
    self.previewPlaceholderLabel.stringValue = @"Preview failed.";
    self.previewReady = NO;
    self.clipboardButton.enabled = NO;
    [self updateStatus:error.localizedDescription ?: @"The SVG preview failed to load."];
}

@end
