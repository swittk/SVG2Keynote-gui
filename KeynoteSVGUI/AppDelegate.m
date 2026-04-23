@import Cocoa;

#import "AppDelegate.h"
#import "SVGPopoverViewController.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) NSStatusItem *statusItem;
@end

static void ActivateCurrentApp(void) {
    [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateAllWindows | NSApplicationActivateIgnoringOtherApps)];
    [NSApp activateIgnoringOtherApps:YES];
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.popover = [[NSPopover alloc] init];
    self.popover.behavior = NSPopoverBehaviorApplicationDefined;
    self.popover.contentSize = NSMakeSize(420.0, 440.0);
    self.popover.contentViewController = [[SVGPopoverViewController alloc] init];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.title = @"SVG2Key";
    button.target = self;
    button.action = @selector(togglePopover:);
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
    ActivateCurrentApp();
}

@end
