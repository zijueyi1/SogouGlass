#include "WindowIDs.h"

double SGInputIdleSeconds(void) {
    return CGEventSourceSecondsSinceLastEventType(
        kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType);
}

CFDataRef SGCopyVisibleWindowIDs(void) {
    CFArrayRef windows = CGWindowListCreate(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (!windows) return NULL;
    CFIndex count = CFArrayGetCount(windows);
    CFMutableDataRef data = CFDataCreateMutable(NULL, count * sizeof(CGWindowID));
    if (!data) { CFRelease(windows); return NULL; }
    CFDataSetLength(data, count * sizeof(CGWindowID));
    CGWindowID *ids = (CGWindowID *)CFDataGetMutableBytePtr(data);
    for (CFIndex i = 0; i < count; ++i) {
        ids[i] = (CGWindowID)(uintptr_t)CFArrayGetValueAtIndex(windows, i);
    }
    CFRelease(windows);
    return data;
}
