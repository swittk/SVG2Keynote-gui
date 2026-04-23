@import Cocoa;
@import WebKit;

#import "SVGPopoverViewController.h"

@interface SVGPopoverViewController ()
@property (nonatomic, strong) WKWebView *previewView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *openButton;
@property (nonatomic, strong) NSButton *exportPDFButton;
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
    previewContainer.layer.backgroundColor = NSColor.whiteColor.CGColor;
    previewContainer.layer.borderColor = NSColor.separatorColor.CGColor;
    previewContainer.layer.borderWidth = 1.0;
    previewContainer.layer.cornerRadius = 6.0;
    previewContainer.layer.masksToBounds = YES;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    self.previewView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    self.previewView.navigationDelegate = self;
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;

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

    self.exportPDFButton = [NSButton buttonWithTitle:@"Copy PDF for Keynote" target:self action:@selector(copyPDFToClipboard:)];
    self.exportPDFButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.exportPDFButton.enabled = NO;

    [previewContainer addSubview:self.previewView];
    [self.view addSubview:previewContainer];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.openButton];
    [self.view addSubview:self.exportPDFButton];

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

        [self.exportPDFButton.centerYAnchor constraintEqualToAnchor:self.openButton.centerYAnchor],
        [self.exportPDFButton.trailingAnchor constraintEqualToAnchor:previewContainer.trailingAnchor],
        [self.exportPDFButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.openButton.trailingAnchor constant:12.0],
    ]];
}

- (void)loadPlaceholder {
    self.previewReady = NO;
    self.exportPDFButton.enabled = NO;
    [self updateStatus:@"Open an SVG file. The app now copies a native vector PDF to the clipboard for Keynote."];
    [self.previewView loadHTMLString:@"<!DOCTYPE html><html><body style=\"margin:0; display:flex; align-items:center; justify-content:center; min-height:100vh; font:13px -apple-system; color:#666; background:#fff;\">Select an SVG file to preview it here.</body></html>" baseURL:nil];
}

- (void)openSVG:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[ @"svg" ];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canCreateDirectories = NO;

    if ([panel runModal] != NSModalResponseOK) {
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
    self.exportPDFButton.enabled = NO;

    [self updateStatus:[NSString stringWithFormat:@"Loading %@…", selectedURL.lastPathComponent ?: @"SVG"]];
    NSString *html = [self HTMLDocumentForSVGString:svgString];
    [self.previewView loadHTMLString:html baseURL:selectedURL.URLByDeletingLastPathComponent];
}

- (void)copyPDFToClipboard:(id)sender {
    if (!self.previewReady) {
        [self updateStatus:@"Wait for the preview to finish loading before copying."];
        return;
    }

    NSData *pdfData = [self.previewView dataWithPDFInsideRect:self.previewView.bounds];
    if (pdfData.length == 0) {
        [self updateStatus:@"Failed to generate PDF data from the SVG preview."];
        return;
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSArray<NSPasteboardType> *types = @[ NSPasteboardTypePDF, @"com.adobe.pdf", @"Apple PDF pasteboard type" ];
    [pasteboard clearContents];
    [pasteboard declareTypes:types owner:nil];

    for (NSPasteboardType type in types) {
        [pasteboard setData:pdfData forType:type];
    }

    [self updateStatus:@"Copied a vector PDF to the clipboard. Paste it into Keynote with Command-V."];
}

- (NSString *)HTMLDocumentForSVGString:(NSString *)svgString {
    NSString *sanitizedSVG = [self sanitizedSVGString:svgString ?: @""];
    return [NSString stringWithFormat:
            @"<!DOCTYPE html>"
            "<html>"
            "<head>"
            "<meta charset=\"utf-8\">"
            "<style>"
            "html, body { margin: 0; padding: 0; width: 100%%; height: 100%%; background: #ffffff; }"
            "body { display: flex; align-items: center; justify-content: center; overflow: hidden; }"
            "svg { display: block; max-width: 100%%; max-height: 100%%; width: auto; height: auto; }"
            "</style>"
            "</head>"
            "<body>%@</body>"
            "</html>",
            sanitizedSVG];
}

- (NSString *)sanitizedSVGString:(NSString *)svgString {
    NSString *sanitized = [svgString copy];
    sanitized = [sanitized stringByReplacingOccurrencesOfString:@"(?is)^\\s*<\\?xml[^>]*>\\s*"
                                                     withString:@""
                                                        options:NSRegularExpressionSearch
                                                          range:NSMakeRange(0, sanitized.length)];
    sanitized = [sanitized stringByReplacingOccurrencesOfString:@"(?is)^\\s*<!DOCTYPE[^>]*(\\[[\\s\\S]*?\\])?>\\s*"
                                                     withString:@""
                                                        options:NSRegularExpressionSearch
                                                          range:NSMakeRange(0, sanitized.length)];
    return sanitized;
}

- (void)updateStatus:(NSString *)statusText {
    self.statusLabel.stringValue = statusText ?: @"";
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.previewReady = YES;
    self.exportPDFButton.enabled = (self.currentSVGString.length > 0);
    NSString *fileName = self.currentFileURL.lastPathComponent ?: @"SVG";
    [self updateStatus:[NSString stringWithFormat:@"%@ loaded. Copy the vector PDF and paste it into Keynote.", fileName]];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.previewReady = NO;
    self.exportPDFButton.enabled = NO;
    [self updateStatus:error.localizedDescription ?: @"The SVG preview failed to load."];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    self.previewReady = NO;
    self.exportPDFButton.enabled = NO;
    [self updateStatus:error.localizedDescription ?: @"The SVG preview failed to load."];
}

@end
