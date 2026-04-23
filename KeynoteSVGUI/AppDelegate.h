@import Cocoa;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSPopoverDelegate>

- (BOOL)isPopoverShown;
- (void)closePopover;
- (void)showPopoverFromStatusItem;

@end
