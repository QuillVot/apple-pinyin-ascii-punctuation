// SPDX-License-Identifier: MIT
// Copyright (c) 2026 PinyinASCII contributors

#import <AppKit/AppKit.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int logFile = -1;

static void usage(FILE *stream) {
    fputs("Usage: pinyin-ascii-input-probe [--log PATH]\n"
          "Open a text input window for manual IME testing.\n"
          "Logging is disabled by default. --log appends JSONL containing test\n"
          "input from this window only, including inserted and marked text.\n"
          "  --help      Show this help and exit.\n", stream);
}

// No global event monitor is installed; only this view calls this logger.
static void record(NSString *kind, NSDictionary *details) {
    if (logFile < 0) return;
    NSMutableDictionary *row = [details mutableCopy];
    row[@"kind"] = kind;
    row[@"time"] = @([NSDate timeIntervalSinceReferenceDate]);
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:row options:0 error:&error];
    if (!json) {
        fprintf(stderr, "Cannot encode log entry: %s\n", error.localizedDescription.UTF8String);
        return;
    }
    NSMutableData *line = [json mutableCopy];
    [line appendBytes:"\n" length:1];
    const char *bytes = line.bytes;
    NSUInteger remaining = line.length;
    while (remaining > 0) {
        ssize_t count = write(logFile, bytes, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            if (count < 0) perror("Cannot write input log");
            else fputs("Cannot write input log: zero-byte write\n", stderr);
            close(logFile);
            logFile = -1;
            return;
        }
        bytes += count;
        remaining -= (NSUInteger)count;
    }
}

static NSString *plainText(id value) {
    return [value isKindOfClass:[NSAttributedString class]] ? [value string] : value;
}

@interface ProbeView : NSTextView
@end

@implementation ProbeView
- (void)keyDown:(NSEvent *)event {
    record(@"keyDown", @{@"keyCode": @(event.keyCode),
                         @"flags": @(event.modifierFlags),
                         @"source": self.inputContext.selectedKeyboardInputSource ?: @"",
                         @"marked": @([self hasMarkedText])});
    [super keyDown:event];
}

- (void)insertText:(id)value replacementRange:(NSRange)range {
    record(@"insertText", @{@"text": plainText(value) ?: @"",
                            @"replacementRange": NSStringFromRange(range)});
    [super insertText:value replacementRange:range];
}

- (void)setMarkedText:(id)value selectedRange:(NSRange)selection replacementRange:(NSRange)replacement {
    record(@"markedText", @{@"text": plainText(value) ?: @"",
                            @"selectedRange": NSStringFromRange(selection),
                            @"replacementRange": NSStringFromRange(replacement)});
    [super setMarkedText:value selectedRange:selection replacementRange:replacement];
}

- (void)doCommandBySelector:(SEL)selector {
    record(@"command", @{@"selector": NSStringFromSelector(selector)});
    [super doCommandBySelector:selector];
}
@end

@interface ProbeController : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) ProbeView *view;
@property(nonatomic, strong) NSTextField *status;
@end

@implementation ProbeController
- (void)addButton:(NSString *)title action:(SEL)action x:(CGFloat)x width:(CGFloat)width {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.frame = NSMakeRect(x, 525, width, 32);
    button.autoresizingMask = NSViewMinYMargin;
    [self.window.contentView addSubview:button];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 120, 920, 580)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"PinyinASCII Input Probe";
    self.window.releasedWhenClosed = NO;
    self.window.minSize = NSMakeSize(680, 320);
    [self addButton:@"ABC" action:@selector(selectABC:) x:20 width:90];
    [self addButton:@"简体拼音" action:@selector(selectPinyin:) x:120 width:130];
    [self addButton:@"Clear" action:@selector(clear:) x:260 width:100];

    self.status = [NSTextField labelWithString:@""];
    self.status.frame = NSMakeRect(20, 490, 880, 26);
    self.status.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.window.contentView addSubview:self.status];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, 880, 460)];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.view = [[ProbeView alloc] initUsingTextLayoutManager:YES];
    self.view.frame = scroll.contentView.bounds;
    self.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.view.richText = NO;
    self.view.font = [NSFont monospacedSystemFontOfSize:19 weight:NSFontWeightRegular];
    self.view.automaticQuoteSubstitutionEnabled = NO;
    self.view.automaticDashSubstitutionEnabled = NO;
    self.view.automaticSpellingCorrectionEnabled = NO;
    self.view.automaticTextReplacementEnabled = NO;
    scroll.documentView = self.view;
    [self.window.contentView addSubview:scroll];

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"PinyinASCII Input Probe"
        action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"PinyinASCII Input Probe"];
    [appMenu addItemWithTitle:@"Quit PinyinASCII Input Probe" action:@selector(terminate:)
        keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [menu addItem:appItem];
    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit"
        action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [menu addItem:editItem];
    NSApp.mainMenu = menu;

    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.view];
    [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refresh:)
        userInfo:nil repeats:YES];
    [self refresh:nil];
    record(@"launch", @{});
}

- (void)refresh:(NSTimer *)timer {
    (void)timer;
    self.status.stringValue = [NSString stringWithFormat:@"Input source: %@ | Logging %@",
        self.view.inputContext.selectedKeyboardInputSource ?: @"<none>",
        logFile >= 0 ? @"enabled (test input is recorded)" : @"disabled"];
}

- (void)selectSource:(NSString *)source {
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.view];
    [self.view.inputContext discardMarkedText];
    self.view.inputContext.selectedKeyboardInputSource = source;
    [self refresh:nil];
    record(@"source", @{@"selected": self.view.inputContext.selectedKeyboardInputSource ?: @""});
}

- (void)selectABC:(id)sender {
    (void)sender;
    [self selectSource:@"com.apple.keylayout.ABC"];
}

- (void)selectPinyin:(id)sender {
    (void)sender;
    [self selectSource:@"com.apple.inputmethod.SCIM.ITABC"];
}

- (void)clear:(id)sender {
    (void)sender;
    [self.view.inputContext discardMarkedText];
    self.view.string = @"";
    [self.window makeFirstResponder:self.view];
    record(@"clear", @{});
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}
@end

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--help") == 0) {
        usage(stdout);
        return 0;
    }
    if (argc != 1 && !(argc == 3 && strcmp(argv[1], "--log") == 0 && argv[2][0])) {
        usage(stderr);
        return 2;
    }
    if (argc == 3) {
        logFile = open(argv[2], O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
        if (logFile < 0) {
            perror("Cannot open input log");
            return 1;
        }
    }
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        __attribute__((objc_precise_lifetime)) ProbeController *controller = [[ProbeController alloc] init];
        app.delegate = controller;
        [app run];
    }
    if (logFile >= 0) close(logFile);
    return 0;
}
