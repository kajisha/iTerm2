//
//  CaptureTrigger.m
//  iTerm
//
//  Created by George Nachman on 5/22/14.
//
//

#import "CaptureTrigger.h"
#import "CommandHistory.h"
#import "iTermAnnouncementViewController.h"
#import "iTermApplicationDelegate.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"  // TODO: Use delegacy? Or something?
#import "ToolbeltView.h"
#import "VT100ScreenMark.h"

// This one cannot be suppressed.
static NSString *const kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier =
    @"NoSyncTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier";

static NSString *const kSuppressCaptureOutputRequiresShellIntegrationWarning =
    @"NoSyncSuppressCaptureOutputRequiresShellIntegrationWarning";
static NSString *const kSuppressCaptureOutputToolNotVisibleWarning =
    @"NoSyncSuppressCaptureOutputToolNotVisibleWarning";

@implementation CapturedOutput

- (void)dealloc {
    [_values release];
    [_trigger release];
    [_mark release];
    [super dealloc];
}

@end


@implementation CaptureTrigger

+ (NSString *)title {
    return @"Capture Output";
}

- (BOOL)takesParameter {
    return YES;
}

- (NSString *)paramPlaceholder {
  return @"Coprocess to run on activation";
}

- (BOOL)capturedOutputToolVisibleInSession:(PTYSession *)aSession {
    if (!aSession.tab.realParentWindow.shouldShowToolbelt) {
        return NO;
    }
    return [ToolbeltView shouldShowTool:kCapturedOutputToolName];
}

- (void)showCaptureOutputToolInSession:(PTYSession *)aSession {
    if (!aSession.tab.realParentWindow.shouldShowToolbelt) {
        [aSession.tab.realParentWindow toggleToolbeltVisibility:nil];
    }
    if (![ToolbeltView shouldShowTool:kCapturedOutputToolName]) {
        [ToolbeltView toggleShouldShowTool:kCapturedOutputToolName];
    }
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    if (!aSession.screen.shellIntegrationInstalled) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kSuppressCaptureOutputRequiresShellIntegrationWarning]) {
            [self showShellIntegrationRequiredAnnouncementInSession:aSession];
        }
    } else if (![self capturedOutputToolVisibleInSession:aSession]) {
        if (![[NSUserDefaults standardUserDefaults] boolForKey:kSuppressCaptureOutputToolNotVisibleWarning]) {
            [self showCapturedOutputToolNotVisibleAnnouncementInSession:aSession];
        }
    }
    CapturedOutput *output = [[[CapturedOutput alloc] init] autorelease];
    output.line = stringLine.stringValue;
    output.trigger = self;
    output.values = [NSArray arrayWithObjects:capturedStrings count:captureCount];
    output.mark = [aSession markAddedAtCursorOfClass:[iTermCapturedOutputMark class]];
    [aSession addCapturedOutput:output];
    return NO;
}

- (void)showCapturedOutputToolNotVisibleAnnouncementInSession:(PTYSession *)aSession {
    NSString *theTitle = @"A Capture Output trigger fired, but the Captured Output tool is not visible.";
    [aSession retain];
    void (^completion)(int selection) = ^(int selection) {
        switch (selection) {
            case -2:
                [aSession release];
                break;

            case 0:
                [self showCaptureOutputToolInSession:aSession];
                break;

            case 1:
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kSuppressCaptureOutputToolNotVisibleWarning];
                break;
        }
    };
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcemenWithTitle:theTitle
                                                        style:kiTermAnnouncementViewStyleWarning
                                                  withActions:@[ @"Show It", @"Silence Warning" ]
                                                   completion:completion];
    [aSession queueAnnouncement:announcement
                     identifier:kSuppressCaptureOutputToolNotVisibleWarning];
}

- (void)showShellIntegrationRequiredAnnouncementInSession:(PTYSession *)aSession {
    NSString *theTitle = @"A Capture Output trigger fired, but Shell Integration is not installed.";
    [aSession retain];
    void (^completion)(int selection) = ^(int selection) {
        switch (selection) {
            case -2:
                [aSession release];
                break;

            case 0:
                [aSession tryToRunShellIntegrationInstaller];
                break;

            case 1:
                [[NSUserDefaults standardUserDefaults] setBool:YES
                                                        forKey:kSuppressCaptureOutputRequiresShellIntegrationWarning];
                break;
        }
    };
    iTermAnnouncementViewController *announcement =
        [iTermAnnouncementViewController announcemenWithTitle:theTitle
                                                        style:kiTermAnnouncementViewStyleWarning
                                                  withActions:@[ @"Install", @"Silence Warning" ]
                                                   completion:completion];
    [aSession queueAnnouncement:announcement
                     identifier:kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier];
}

- (void)activateOnOutput:(CapturedOutput *)capturedOutput inSession:(PTYSession *)session {
    if (!session.hasCoprocess) {
        NSString *command = [self paramWithBackreferencesReplacedWithValues:capturedOutput.values];
        if (command) {
            [session launchCoprocessWithCommand:command];
        }
    } else {
        iTermAnnouncementViewController *announcement =
            [iTermAnnouncementViewController announcemenWithTitle:@"Can't run two coprocesses at once."
                                                            style:kiTermAnnouncementViewStyleWarning
                                                      withActions:@[ ]
                                                       completion:^(int selection) { }];
        announcement.timeout = 2;
        [session queueAnnouncement:announcement
                        identifier:kTwoCoprocessesCanNotRunAtOnceAnnouncmentIdentifier];
    }
    [session takeFocus];
}

@end
