// SPDX-License-Identifier: MIT
// Copyright (c) 2026 PinyinASCII contributors

#include <ApplicationServices/ApplicationServices.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(FILE *stream) {
    fputs("Usage: pinyin-ascii-ax-range PID\n"
          "Inspect marked-text range metadata on the focused element of PID.\n"
          "Uses a 50 ms AX messaging timeout; does not read text or request permissions.\n"
          "  --help      Show this help and exit.\n", stream);
}

static void printType(CFTypeRef value) {
    if (!value) {
        fputs("type=none", stdout);
        return;
    }
    CFTypeID type = CFGetTypeID(value);
    CFStringRef name = CFCopyTypeIDDescription(type);
    char buffer[128];
    const char *description = name && CFStringGetCString(name, buffer, sizeof buffer,
        kCFStringEncodingUTF8) ? buffer : "unknown";
    printf("type=%lu(%s)", (unsigned long)type, description);
    if (name) CFRelease(name);
}

// Inspect only range/type metadata, never the focused element's text value.
static void printRange(AXUIElementRef focused, CFStringRef attribute, const char *name) {
    CFTypeRef value = NULL;
    AXError error = AXUIElementCopyAttributeValue(focused, attribute, &value);
    printf("attribute=%s error=%d ", name, (int)error);
    printType(value);
    if (value && CFGetTypeID(value) == AXValueGetTypeID()) {
        AXValueType type = AXValueGetType(value);
        printf(" axValueType=%d", (int)type);
        if (type == kAXValueCFRangeType) {
            CFRange range;
            if (AXValueGetValue(value, kAXValueCFRangeType, &range)) {
                printf(" range=%ld,%ld", range.location, range.length);
            }
        }
    }
    putchar('\n');
    if (value) CFRelease(value);
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--help") == 0) {
        usage(stdout);
        return 0;
    }
    if (argc != 2 || !argv[1][0]) {
        usage(stderr);
        return 2;
    }
    for (const char *p = argv[1]; *p; p++) {
        if (*p < '0' || *p > '9') {
            fputs("PID must contain decimal digits only.\n", stderr);
            return 2;
        }
    }
    errno = 0;
    char *end = NULL;
    long number = strtol(argv[1], &end, 10);
    if (errno == ERANGE || *end || number <= 0 || number > INT_MAX) {
        fputs("PID must be between 1 and INT_MAX.\n", stderr);
        return 2;
    }

    AXUIElementRef system = AXUIElementCreateSystemWide();
    AXError error = AXUIElementSetMessagingTimeout(system, 0.05f);
    CFRelease(system);
    if (error != kAXErrorSuccess) {
        fprintf(stderr, "Cannot set AX messaging timeout: error=%d\n", (int)error);
        return 1;
    }

    AXUIElementRef application = AXUIElementCreateApplication((pid_t)number);
    CFTypeRef focused = NULL;
    error = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute, &focused);
    printf("pid=%ld trusted=%d focusedError=%d ", number, AXIsProcessTrusted(), (int)error);
    printType(focused);
    putchar('\n');
    int status = 1;
    if (error == kAXErrorSuccess && focused && CFGetTypeID(focused) == AXUIElementGetTypeID()) {
        printRange((AXUIElementRef)focused, CFSTR("AXTextInputMarkedRange"),
            "AXTextInputMarkedRange");
        // The runtime attribute also exists on SDKs without its named constant.
        printRange((AXUIElementRef)focused, CFSTR("AXTextInputMarkedTextMarkerRange"),
            "AXTextInputMarkedTextMarkerRange");
        status = 0;
    }
    if (focused) CFRelease(focused);
    CFRelease(application);
    return status;
}
