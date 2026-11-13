// Private MultitouchSupport.framework types (loaded at runtime via dlopen).
#include <CoreFoundation/CoreFoundation.h>

typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;          // 4 = make touch, 5 = touching
    int fingerId;
    int handId;
    MTVector normalized; // 0..1, origin bottom-left
    float size;
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int zero2[2];
    float density;
} MTTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(MTDeviceRef, const MTTouch *, int, double, int);
