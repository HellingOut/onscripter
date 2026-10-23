#import <UIKit/UIKit.h>

void showMissingDataAlert(const char *message)
{
    NSString *text = message ? [NSString stringWithUTF8String:message]
                             : @"No game data found.";
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"ONScripter"
                                                    message:text
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
    [alert release];
}
