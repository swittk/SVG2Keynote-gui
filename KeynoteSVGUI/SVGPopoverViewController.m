@import Cocoa;
@import WebKit;

#import "AppDelegate.h"
#import "SVGPopoverViewController.h"
#import "wrapper.h"

@interface SVGPopoverViewController ()
@property (nonatomic, strong) WKWebView *previewView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *openButton;
@property (nonatomic, strong) NSButton *clipboardButton;
@property (nonatomic, strong) NSButton *quitButton;
@property (nonatomic, copy) NSString *currentSVGString;
@property (nonatomic, strong) NSURL *currentFileURL;
@property (nonatomic, assign) BOOL previewReady;
@end

@implementation SVGPopoverViewController

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 420.0, 440.0)];
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

    self.quitButton = [NSButton buttonWithTitle:@"Quit" target:self action:@selector(quitApp:)];
    self.quitButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.clipboardButton = [NSButton buttonWithTitle:@"Copy Keynote Shapes" target:self action:@selector(copyToClipboard:)];
    self.clipboardButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.clipboardButton.enabled = NO;

    [previewContainer addSubview:self.previewView];
    [self.view addSubview:previewContainer];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.openButton];
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

        [self.quitButton.centerYAnchor constraintEqualToAnchor:self.openButton.centerYAnchor],
        [self.quitButton.leadingAnchor constraintEqualToAnchor:self.openButton.trailingAnchor constant:12.0],

        [self.clipboardButton.centerYAnchor constraintEqualToAnchor:self.openButton.centerYAnchor],
        [self.clipboardButton.trailingAnchor constraintEqualToAnchor:previewContainer.trailingAnchor],
        [self.clipboardButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.quitButton.trailingAnchor constant:12.0],
    ]];
}

- (void)loadPlaceholder {
    self.previewReady = NO;
    self.clipboardButton.enabled = NO;
    [self updateStatus:@"Open an SVG file. Copy places editable Keynote shapes on the clipboard."];
    [self.previewView loadHTMLString:@"<!DOCTYPE html><html><body style=\"margin:0; display:flex; align-items:center; justify-content:center; min-height:100vh; font:13px -apple-system; color:#666; background:transparent;\">Select an SVG file to preview it here.</body></html>" baseURL:nil];
}

- (void)activateForForegroundInteraction {
    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)openSVG:(id)sender {
    [self activateForForegroundInteraction];

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[ @"svg" ];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canCreateDirectories = NO;
    panel.directoryURL = self.currentFileURL.URLByDeletingLastPathComponent;

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
    NSData *metadata = [wrapper generateClipboardMetadataWithDocumentUUIDString:documentUUIDString];
    NSData *clipboardDescription = [wrapper generateClipboardDescriptionForDrawableCount:drawableCount];

    self.clipboardButton.enabled = self.previewReady;

    if (clipboardData.length == 0 || metadata.length == 0 || clipboardDescription.length == 0) {
        [self updateStatus:@"Failed to generate Keynote clipboard data from the SVG."];
        return;
    }

    [self writeKeynoteClipboardData:clipboardData
                           metadata:metadata
                    clipboardDescription:clipboardDescription
                      drawableCount:drawableCount];
    [self updateStatus:@"Copied editable Keynote data to the clipboard. Paste it into Keynote with Command-V."];
}

- (void)quitApp:(id)sender {
    [NSApp terminate:sender];
}

- (void)writeKeynoteClipboardData:(NSData *)clipboardData
                         metadata:(NSData *)metadata
             clipboardDescription:(NSData *)clipboardDescription
                    drawableCount:(NSInteger)drawableCount {
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

    [pasteboard declareTypes:types owner:nil];
    [pasteboard setData:clipboardData forType:nativeDataType];
    [pasteboard setData:metadata forType:metadataType];
    [pasteboard setData:clipboardDescription forType:descriptionType];

    NSData *markerData = [NSData data];
    for (NSPasteboardType type in types) {
        if ([type isEqualToString:nativeDataType] || [type isEqualToString:metadataType] || [type isEqualToString:descriptionType]) {
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
    [self updateStatus:[NSString stringWithFormat:@"%@ loaded. Copy the native Keynote shapes and paste them into Keynote.", fileName]];
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
