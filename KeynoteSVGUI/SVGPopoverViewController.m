@import Cocoa;
@import WebKit;

#import "AppDelegate.h"
#import "SVGPopoverViewController.h"
#import "wrapper.h"

static NSString *const kCompatibilityProfileDefaultsKey = @"CompatibilityProfile";

@interface SVGPopoverViewController ()
@property (nonatomic, strong) WKWebView *previewView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *openButton;
@property (nonatomic, strong) NSButton *syncButton;
@property (nonatomic, strong) NSButton *saveClipboardButton;
@property (nonatomic, strong) NSButton *clipboardButton;
@property (nonatomic, strong) NSButton *quitButton;
@property (nonatomic, copy) NSString *currentSVGString;
@property (nonatomic, strong) NSURL *currentFileURL;
@property (nonatomic, assign) BOOL previewReady;
@end

@implementation SVGPopoverViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 660.0, 440.0)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self buildInterface];
    [self loadPlaceholder];
}

- (void)buildInterface {
    NSView *previewContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    previewContainer.translatesAutoresizingMaskIntoConstraints = NO;
    previewContainer.wantsLayer = YES;
    previewContainer.layer.backgroundColor = NSColor.clearColor.CGColor;
    previewContainer.layer.borderColor = [NSColor colorWithCalibratedWhite:0.78 alpha:1.0].CGColor;
    previewContainer.layer.borderWidth = 1.0;
    previewContainer.layer.cornerRadius = 6.0;
    previewContainer.layer.masksToBounds = YES;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    self.previewView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    self.previewView.navigationDelegate = self;
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.previewView setValue:@NO forKey:@"drawsBackground"];

    self.statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.bezeled = NO;
    self.statusLabel.drawsBackground = NO;
    self.statusLabel.editable = NO;
    self.statusLabel.font = [NSFont systemFontOfSize:12.0];
    self.statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.statusLabel.selectable = NO;
    self.statusLabel.stringValue = @"";
    self.statusLabel.usesSingleLineMode = NO;

    self.openButton = [NSButton buttonWithTitle:@"Open SVG File" target:self action:@selector(openSVG:)];
    self.openButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.syncButton = [NSButton buttonWithTitle:@"Resync Compatibility" target:self action:@selector(resyncCompatibility:)];
    self.syncButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.saveClipboardButton = [NSButton buttonWithTitle:@"Save Clipboard..." target:self action:@selector(saveClipboard:)];
    self.saveClipboardButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.quitButton = [NSButton buttonWithTitle:@"Quit" target:self action:@selector(quitApp:)];
    self.quitButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.clipboardButton = [NSButton buttonWithTitle:@"Copy Keynote Shapes" target:self action:@selector(copyToClipboard:)];
    self.clipboardButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.clipboardButton.enabled = NO;

    [previewContainer addSubview:self.previewView];
    [self.view addSubview:previewContainer];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.openButton];
    [self.view addSubview:self.syncButton];
    [self.view addSubview:self.saveClipboardButton];
    [self.view addSubview:self.quitButton];
    [self.view addSubview:self.clipboardButton];

    [NSLayoutConstraint activateConstraints:@[
        [previewContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:16.0],
        [previewContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [previewContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [previewContainer.heightAnchor constraintEqualToConstant:280.0],

        [self.previewView.topAnchor constraintEqualToAnchor:previewContainer.topAnchor],
        [self.previewView.leadingAnchor constraintEqualToAnchor:previewContainer.leadingAnchor],
        [self.previewView.trailingAnchor constraintEqualToAnchor:previewContainer.trailingAnchor],
        [self.previewView.bottomAnchor constraintEqualToAnchor:previewContainer.bottomAnchor],

        [self.statusLabel.topAnchor constraintEqualToAnchor:previewContainer.bottomAnchor constant:12.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:previewContainer.leadingAnchor],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:previewContainer.trailingAnchor],

        [self.openButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12.0],
        [self.openButton.leadingAnchor constraintEqualToAnchor:previewContainer.leadingAnchor],
        [self.openButton.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-16.0],

        [self.syncButton.centerYAnchor constraintEqualToAnchor:self.openButton.centerYAnchor],
        [self.syncButton.leadingAnchor constraintEqualToAnchor:self.openButton.trailingAnchor constant:12.0],

        [self.saveClipboardButton.centerYAnchor constraintEqualToAnchor:self.openButton.centerYAnchor],
        [self.saveClipboardButton.leadingAnchor constraintEqualToAnchor:self.syncButton.trailingAnchor constant:12.0],

        [self.quitButton.centerYAnchor constraintEqualToAnchor:self.openButton.centerYAnchor],
        [self.quitButton.leadingAnchor constraintEqualToAnchor:self.saveClipboardButton.trailingAnchor constant:12.0],

        [self.clipboardButton.centerYAnchor constraintEqualToAnchor:self.openButton.centerYAnchor],
        [self.clipboardButton.trailingAnchor constraintEqualToAnchor:previewContainer.trailingAnchor],
        [self.clipboardButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.quitButton.trailingAnchor constant:12.0],
    ]];
}

- (void)loadPlaceholder {
    self.previewReady = NO;
    self.clipboardButton.enabled = NO;
    NSString *status = @"Open an SVG file to preview and copy editable Keynote shapes, or save the current clipboard back out as SVG or PNG.";
    NSDictionary<NSString *, id> *compatibilityProfile = [self savedCompatibilityProfile];
    if (compatibilityProfile.count > 0) {
        status = [status stringByAppendingFormat:@" Active compatibility: %@.", [self compatibilitySummaryForProfile:compatibilityProfile]];
    }
    [self updateStatus:status];
    [self.previewView loadHTMLString:@"<!DOCTYPE html><html><body style=\"margin:0; display:flex; align-items:center; justify-content:center; min-height:100vh; font:13px -apple-system; color:#666; background:transparent;\">Select an SVG file to preview it here.</body></html>" baseURL:nil];
}

- (void)activateForForegroundInteraction {
    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    [NSApp activateIgnoringOtherApps:YES];
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
    NSStringEncoding usedEncoding = 0;
    NSString *svgString = [NSString stringWithContentsOfURL:selectedURL usedEncoding:&usedEncoding error:&error];
    if (svgString == nil) {
        NSData *data = [NSData dataWithContentsOfURL:selectedURL options:0 error:&error];
        if (data != nil) {
            svgString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
    }

    if (svgString == nil) {
        [self updateStatus:[NSString stringWithFormat:@"Failed to read %@.", selectedURL.lastPathComponent ?: @"the selected file"]];
        return;
    }

    self.currentFileURL = selectedURL;
    self.currentSVGString = svgString;
    self.previewReady = NO;
    self.clipboardButton.enabled = NO;

    [self updateStatus:[NSString stringWithFormat:@"Loading %@…", selectedURL.lastPathComponent ?: @"SVG"]];
    NSURL *readAccessURL = selectedURL.URLByDeletingLastPathComponent ?: selectedURL;
    [self.previewView loadFileURL:selectedURL allowingReadAccessToURL:readAccessURL];
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

        NSString *status = @"Copied editable Keynote data to the clipboard. Paste it into Keynote with Command-V.";
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
    NSMutableArray<NSPasteboardType> *types = [NSMutableArray arrayWithArray:@[
        nativeDataType,
        metadataType,
        descriptionType,
        hasNativeDrawablesType,
        @"com.apple.iWork.pasteboardState.hasNativeTypes",
        @"com.apple.iWork.pasteboardState.drawableInfoKinds-1",
        @"com.apple.iWork.pasteboardState.elementKinds-2",
        @"com.apple.iWork.pasteboardState.countOfObject-2",
        @"com.apple.iWork.pasteboardState.maxinlinenestingdepth-1",
    ]];
    if (drawableCount < 1) {
        drawableCount = 1;
    }
    [types addObject:[NSString stringWithFormat:@"com.apple.iWork.pasteboardState.numberOfDrawables-%ld", (long)drawableCount]];
    [types addObject:[NSString stringWithFormat:@"com.apple.iWork.pasteboardState.numberOfTopLevelDrawables-%ld", (long)drawableCount]];
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

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.previewReady = YES;
    self.clipboardButton.enabled = (self.currentSVGString.length > 0);
    NSString *fileName = self.currentFileURL.lastPathComponent ?: @"SVG";
    NSString *status = [NSString stringWithFormat:@"%@ loaded. Copy the native Keynote shapes and paste them into Keynote.", fileName];
    NSDictionary<NSString *, id> *compatibilityProfile = [self savedCompatibilityProfile];
    if (compatibilityProfile.count > 0) {
        status = [status stringByAppendingFormat:@" Active compatibility: %@.", [self compatibilitySummaryForProfile:compatibilityProfile]];
    }
    [self updateStatus:status];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.previewReady = NO;
    self.clipboardButton.enabled = NO;
    [self updateStatus:error.localizedDescription ?: @"The SVG preview failed to load."];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.previewReady = NO;
    self.clipboardButton.enabled = NO;
    [self updateStatus:error.localizedDescription ?: @"The SVG preview failed to load."];
}

@end
