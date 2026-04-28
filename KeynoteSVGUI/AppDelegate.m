@import Cocoa;

#import "AppDelegate.h"
#import "SVGPopoverViewController.h"

@class AppDelegate;

@interface AppDelegate (StatusItemDragSupport)
- (void)configureStatusItemWindowForDragDestination:(NSWindow *)window;
- (BOOL)statusItemCanAcceptPasteboard:(NSPasteboard *)pasteboard;
- (void)statusItemDidBeginDragHover;
- (BOOL)handleStatusItemDropFromPasteboard:(NSPasteboard *)pasteboard;
- (void)togglePopover:(id)sender;
@end

@interface SVGStatusItemView : NSView <NSDraggingDestination>
@property (nonatomic, weak) AppDelegate *owner;
@property (nonatomic, strong) NSImage *image;
@property (nonatomic, assign, getter=isPopoverHighlighted) BOOL popoverHighlighted;
@property (nonatomic, assign, getter=isDragHighlighted) BOOL dragHighlighted;
@property (nonatomic, assign) BOOL dragOperationPerformed;
- (instancetype)initWithOwner:(AppDelegate *)owner image:(NSImage *)image frame:(NSRect)frame;
@end

@interface AppDelegate ()
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) SVGStatusItemView *statusItemView;
@property (nonatomic, strong) id eventMonitor;
@end

static void ActivateCurrentApp(void) {
    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    [NSApp activateIgnoringOtherApps:YES];
}

static NSImage *BundleApplicationIconImage(void) {
    NSString *iconPath = [NSBundle.mainBundle pathForResource:@"AppIcon" ofType:@"icns"];
    if (iconPath.length > 0) {
        NSImage *iconImage = [[NSImage alloc] initWithContentsOfFile:iconPath];
        if (iconImage != nil) {
            return iconImage;
        }
    }

    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
    NSImage *workspaceIcon = [workspace iconForFile:NSBundle.mainBundle.bundlePath];
    if (workspaceIcon != nil) {
        return workspaceIcon;
    }

    return nil;
}

@implementation SVGStatusItemView

- (instancetype)initWithOwner:(AppDelegate *)owner image:(NSImage *)image frame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _owner = owner;
        _image = image;
        [self registerForDraggedTypes:[SVGPopoverViewController supportedSVGPasteboardTypes]];
        self.toolTip = @"SVG2Key";
    }
    return self;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.owner configureStatusItemWindowForDragDestination:self.window];
}

- (void)drawRect:(NSRect)dirtyRect {
    BOOL highlighted = self.isPopoverHighlighted || self.isDragHighlighted;
    [self.owner.statusItem drawStatusBarBackgroundInRect:self.bounds withHighlight:highlighted];

    NSImage *statusImage = self.image;
    if (statusImage != nil) {
        NSColor *tintColor = highlighted ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor;
        NSImage *tintedImage = [self tintedStatusImage:statusImage color:tintColor];
        CGFloat horizontalInset = 0.5;
        CGFloat verticalInset = 0.5;
        CGFloat dimension = floor(MIN(NSWidth(self.bounds) - (horizontalInset * 2.0),
                                      NSHeight(self.bounds) - (verticalInset * 2.0)));
        NSRect imageRect = NSMakeRect(floor((NSWidth(self.bounds) - dimension) / 2.0),
                                      floor((NSHeight(self.bounds) - dimension) / 2.0) + 0.5,
                                      dimension,
                                      dimension);
        [tintedImage drawInRect:imageRect];
    }
    [super drawRect:dirtyRect];
}

- (NSImage *)tintedStatusImage:(NSImage *)image color:(NSColor *)color {
    NSImage *tintedImage = [[NSImage alloc] initWithSize:image.size];
    [tintedImage lockFocus];
    [color set];
    NSRectFill(NSMakeRect(0.0, 0.0, image.size.width, image.size.height));
    [image drawInRect:NSMakeRect(0.0, 0.0, image.size.width, image.size.height)
             fromRect:NSZeroRect
            operation:NSCompositingOperationDestinationIn
             fraction:1.0];
    [tintedImage unlockFocus];
    return tintedImage;
}

- (void)setPopoverHighlighted:(BOOL)popoverHighlighted {
    if (_popoverHighlighted == popoverHighlighted) {
        return;
    }

    _popoverHighlighted = popoverHighlighted;
    [self setNeedsDisplay:YES];
}

- (void)setDragHighlighted:(BOOL)dragHighlighted {
    if (_dragHighlighted == dragHighlighted) {
        return;
    }

    _dragHighlighted = dragHighlighted;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    [self.owner togglePopover:self];
}

- (void)rightMouseDown:(NSEvent *)event {
    [self.owner togglePopover:self];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    BOOL canAccept = [self.owner statusItemCanAcceptPasteboard:sender.draggingPasteboard];
    NSLog(@"[SVGMenuBar] status draggingEntered types=%@ canAccept=%d", sender.draggingPasteboard.types, canAccept);
    self.dragOperationPerformed = NO;
    self.dragHighlighted = canAccept;
    if (!canAccept) {
        return NSDragOperationNone;
    }

    [self.owner statusItemDidBeginDragHover];
    return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    BOOL canAccept = [self.owner statusItemCanAcceptPasteboard:sender.draggingPasteboard];
    NSLog(@"[SVGMenuBar] status draggingUpdated types=%@ canAccept=%d", sender.draggingPasteboard.types, canAccept);
    self.dragHighlighted = canAccept;
    return canAccept ? NSDragOperationCopy : NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    NSLog(@"[SVGMenuBar] status draggingExited");
    self.dragHighlighted = NO;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    BOOL canAccept = [self.owner statusItemCanAcceptPasteboard:sender.draggingPasteboard];
    NSLog(@"[SVGMenuBar] status prepareForDragOperation types=%@ canAccept=%d", sender.draggingPasteboard.types, canAccept);
    return canAccept;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.dragHighlighted = NO;
    self.dragOperationPerformed = YES;
    BOOL handled = [self.owner handleStatusItemDropFromPasteboard:sender.draggingPasteboard];
    NSLog(@"[SVGMenuBar] status performDragOperation handled=%d", handled);
    return handled;
}

- (void)draggingEnded:(id<NSDraggingInfo>)sender {
    NSPoint locationInWindow = sender.draggingLocation;
    NSPoint locationInView = [self convertPoint:locationInWindow fromView:nil];
    BOOL endedInside = NSPointInRect(locationInView, self.bounds);
    NSLog(@"[SVGMenuBar] status draggingEnded performed=%d endedInside=%d locationInView=%@", self.dragOperationPerformed, endedInside, NSStringFromPoint(locationInView));
    if (!self.dragOperationPerformed && endedInside && [self.owner statusItemCanAcceptPasteboard:sender.draggingPasteboard]) {
        self.dragOperationPerformed = YES;
        [self.owner handleStatusItemDropFromPasteboard:sender.draggingPasteboard];
    }
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
    NSLog(@"[SVGMenuBar] status concludeDragOperation");
    self.dragHighlighted = NO;
    self.dragOperationPerformed = NO;
}

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.popover = [[NSPopover alloc] init];
    self.popover.behavior = NSPopoverBehaviorApplicationDefined;
    self.popover.contentSize = NSMakeSize(400.0, 300.0);
    self.popover.contentViewController = [[SVGPopoverViewController alloc] init];
    self.popover.delegate = self;

    NSImage *applicationIconImage = BundleApplicationIconImage();
    if (applicationIconImage != nil) {
        NSApp.applicationIconImage = applicationIconImage;
    }

    CGFloat statusHeight = NSStatusBar.systemStatusBar.thickness;
    CGFloat statusWidth = statusHeight + 1.0;
    NSImage *statusImage = [NSImage imageNamed:@"Icon"];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:statusWidth];
    self.statusItemView = [[SVGStatusItemView alloc] initWithOwner:self
                                                             image:statusImage
                                                             frame:NSMakeRect(0.0, 0.0, statusWidth, statusHeight)];
    self.statusItem.view = self.statusItemView;
    [self configureStatusItemWindowForDragDestination:self.statusItemView.window];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self showPopover:nil];
    return YES;
}

- (SVGPopoverViewController *)popoverController {
    return (SVGPopoverViewController *)self.popover.contentViewController;
}

- (NSView *)statusAnchorView {
    return self.statusItemView ?: self.statusItem.button;
}

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover performClose:sender];
        return;
    }

    [self showPopoverFromStatusItem];
}

- (void)showPopover:(id)sender {
    [self showPopoverFromStatusItem];
}

- (BOOL)isPopoverShown {
    return self.popover.isShown;
}

- (void)closePopover {
    if (self.popover.isShown) {
        [self.popover performClose:nil];
    }
}

- (void)showPopoverFromStatusItem {
    NSView *anchorView = [self statusAnchorView];
    if (anchorView == nil) {
        return;
    }

    [[self popoverController] view];
    ActivateCurrentApp();
    self.statusItemView.popoverHighlighted = YES;
    [self.popover showRelativeToRect:anchorView.bounds ofView:anchorView preferredEdge:NSRectEdgeMinY];
    [self installEventMonitor];
    ActivateCurrentApp();
}

- (void)popoverDidClose:(NSNotification *)notification {
    self.statusItemView.popoverHighlighted = NO;
    [self removeEventMonitor];
}

- (void)installEventMonitor {
    if (self.eventMonitor != nil) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDown |
                                                                       NSEventMaskRightMouseDown |
                                                                       NSEventMaskOtherMouseDown |
                                                                       NSEventMaskKeyDown)
                                                              handler:^NSEvent * _Nullable(NSEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || !strongSelf.popover.isShown) {
            return event;
        }

        NSWindow *popoverWindow = strongSelf.popover.contentViewController.view.window;
        NSWindow *anchorWindow = strongSelf.statusAnchorView.window;
        if (event.window == popoverWindow || event.window == anchorWindow) {
            return event;
        }

        [strongSelf closePopover];
        return event;
    }];
}

- (void)removeEventMonitor {
    if (self.eventMonitor == nil) {
        return;
    }

    [NSEvent removeMonitor:self.eventMonitor];
    self.eventMonitor = nil;
}

- (BOOL)statusItemCanAcceptPasteboard:(NSPasteboard *)pasteboard {
    BOOL canAccept = [[self popoverController] canImportSVGFromPasteboard:pasteboard];
    NSLog(@"[SVGMenuBar] statusItemCanAcceptPasteboard types=%@ canAccept=%d", pasteboard.types, canAccept);
    return canAccept;
}

- (void)configureStatusItemWindowForDragDestination:(NSWindow *)window {
    if (window == nil) {
        return;
    }

    [window registerForDraggedTypes:[SVGPopoverViewController supportedSVGPasteboardTypes]];
    window.delegate = (id<NSWindowDelegate>)self;
    NSLog(@"[SVGMenuBar] configured status item window for drags %@", window);
}

- (void)statusItemDidBeginDragHover {
    ActivateCurrentApp();
    if (self.popover.isShown) {
        [self closePopover];
    }
}

- (BOOL)handleStatusItemDropFromPasteboard:(NSPasteboard *)pasteboard {
    ActivateCurrentApp();
    BOOL imported = [[self popoverController] importSVGFromPasteboard:pasteboard];
    NSLog(@"[SVGMenuBar] handleStatusItemDropFromPasteboard types=%@ imported=%d", pasteboard.types, imported);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showPopoverFromStatusItem];
    });
    return imported;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    BOOL canAccept = [self statusItemCanAcceptPasteboard:sender.draggingPasteboard];
    NSLog(@"[SVGMenuBar] window draggingEntered types=%@ canAccept=%d", sender.draggingPasteboard.types, canAccept);
    self.statusItemView.dragHighlighted = canAccept;
    if (!canAccept) {
        return NSDragOperationNone;
    }

    [self statusItemDidBeginDragHover];
    return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    BOOL canAccept = [self statusItemCanAcceptPasteboard:sender.draggingPasteboard];
    NSLog(@"[SVGMenuBar] window draggingUpdated types=%@ canAccept=%d", sender.draggingPasteboard.types, canAccept);
    self.statusItemView.dragHighlighted = canAccept;
    return canAccept ? NSDragOperationCopy : NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender {
    NSLog(@"[SVGMenuBar] window draggingExited");
    self.statusItemView.dragHighlighted = NO;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    BOOL canAccept = [self statusItemCanAcceptPasteboard:sender.draggingPasteboard];
    NSLog(@"[SVGMenuBar] window prepareForDragOperation types=%@ canAccept=%d", sender.draggingPasteboard.types, canAccept);
    return canAccept;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.statusItemView.dragHighlighted = NO;
    BOOL handled = [self handleStatusItemDropFromPasteboard:sender.draggingPasteboard];
    NSLog(@"[SVGMenuBar] window performDragOperation handled=%d", handled);
    return handled;
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {
    NSLog(@"[SVGMenuBar] window concludeDragOperation");
    self.statusItemView.dragHighlighted = NO;
}

@end
