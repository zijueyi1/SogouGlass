#include <CoreGraphics/CoreGraphics.h>
// Swift 不直接暴露 CGWindowListCreate 的裸指针数组；转成拥有自身内存的 Data。
CFDataRef _Nullable SGCopyVisibleWindowIDs(void) CF_RETURNS_RETAINED;
double SGInputIdleSeconds(void);
