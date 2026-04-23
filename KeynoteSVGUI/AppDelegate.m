@import Cocoa;

#import "AppDelegate.h"
#import "SVGPopoverViewController.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) id eventMonitor;
@end

static void ActivateCurrentApp(void) {
    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    [NSApp activateIgnoringOtherApps:YES];
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.popover = [[NSPopover alloc] init];
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.contentSize = NSMakeSize(420.0, 440.0);
    self.popover.contentViewController = [[SVGPopoverViewController alloc] init];
    self.popover.delegate = self;

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.title = @"SVG2Key";
    button.target = self;
    button.action = @selector(togglePopover:);
    [button sendActionOn:(NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown)];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self showPopover:nil];
    return YES;
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
    NSStatusBarButton *button = self.statusItem.button;
    if (button == nil) {
        return;
    }

    ActivateCurrentApp();
    [self.popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMinY];
    [self installEventMonitor];
    ActivateCurrentApp();
}

- (void)popoverDidClose:(NSNotification *)notification {
    [self removeEventMonitor];
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    [self closePopover];
}

- (void)installEventMonitor {
    if (self.eventMonitor != nil) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown | NSEventMaskKeyDown)
                                                              handler:^NSEvent * _Nullable(NSEvent *event) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || !strongSelf.popover.isShown) {
            return event;
        }

        NSWindow *popoverWindow = strongSelf.popover.contentViewController.view.window;
        NSStatusBarButton *button = strongSelf.statusItem.button;
        NSWindow *buttonWindow = button.window;
        if (event.window == popoverWindow || event.window == buttonWindow) {
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

@end
