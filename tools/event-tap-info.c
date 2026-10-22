// SPDX-License-Identifier: MIT
// Copyright (c) 2026 PinyinASCII contributors

#include <CoreGraphics/CoreGraphics.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(FILE *stream) {
    fputs("Usage: pinyin-ascii-event-tap-info\n"
          "List installed event taps without creating a tap or reading key events.\n"
          "CGGetEventTapList resets existing taps' min/max latency statistics.\n"
          "  --help      Show this help and exit.\n", stream);
}

static const char *locationName(CGEventTapLocation location) {
    switch (location) {
        case kCGHIDEventTap: return "hid";
        case kCGSessionEventTap: return "session";
        case kCGAnnotatedSessionEventTap: return "annotated-session";
        default: return "unknown";
    }
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--help") == 0) {
        usage(stdout);
        return 0;
    }
    if (argc != 1) {
        usage(stderr);
        return 2;
    }

    uint32_t capacity = 0;
    CGError error = CGGetEventTapList(0, NULL, &capacity);
    if (error != kCGErrorSuccess) {
        fprintf(stderr, "Cannot count event taps: error=%d\n", (int)error);
        return 1;
    }
    if (capacity == 0) {
        puts("tap_count=0");
        return 0;
    }
    CGEventTapInformation *taps = calloc(capacity, sizeof *taps);
    if (!taps) {
        fputs("Cannot allocate event tap list.\n", stderr);
        return 1;
    }
    uint32_t count = 0;
    error = CGGetEventTapList(capacity, taps, &count);
    if (error != kCGErrorSuccess) {
        fprintf(stderr, "Cannot list event taps: error=%d\n", (int)error);
        free(taps);
        return 1;
    }
    uint32_t listed = count < capacity ? count : capacity;
    printf("tap_count=%" PRIu32 " listed=%" PRIu32 "\n", count, listed);
    for (uint32_t i = 0; i < listed; i++) {
        const CGEventTapInformation *tap = &taps[i];
        printf("id=%" PRIu32 " pid=%ld target_pid=%ld enabled=%u location=%s(%u)"
               " interest=0x%016" PRIx64 "\n",
            tap->eventTapID, (long)tap->tappingProcess, (long)tap->processBeingTapped,
            tap->enabled ? 1U : 0U, locationName(tap->tapPoint), (unsigned)tap->tapPoint,
            (uint64_t)tap->eventsOfInterest);
    }
    free(taps);
    if (count > capacity) {
        fputs("The event tap list grew during enumeration; this snapshot is truncated.\n", stderr);
        return 1;
    }
    return 0;
}
