@import Cocoa;

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (BOOL)isPopoverShown;
- (void)closePopover;
- (void)showPopoverFromStatusItem;

@end
