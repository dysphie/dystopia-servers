#if defined _debugoverlays_included_
  #endinput
#endif
#define _debugoverlays_included_

#define DRAW_TIME_DEFAULT -1.0

native void DrawLine(
        float origin[3],
        float target[3],
        int r = 0,
        int g = 0,
        int b = 0,
        int noDepthTest = 0,
        float duration = DRAW_TIME_DEFAULT);

native void DrawSweptBox(
        float start[3],
        float end[3],
        float mins[3],
        float maxs[3],
        float angles[3] = {0.0, 0.0, 0.0},
        int r = 0,
        int g = 0,
        int b = 0,
        int a = 255,
        float duration = DRAW_TIME_DEFAULT);

native void DrawSphere(
        float position[3],
        float radius,
        float angles[3] = {0.0, 0.0, 0.0},
        int r = 0,
        int g = 0,
        int b = 0,
        int a = 255,
        bool bNoDepthTest = false,
        float duration = DRAW_TIME_DEFAULT);


native void DrawText(float origin[3], const char[] text, bool bViewCheck = true, float duration = DRAW_TIME_DEFAULT);

native void DrawBox(
        float origin[3],
        float mins[3],
        float maxs[3],
        float angles[3] = {0.0, 0.0, 0.0},
        int r = 0,
        int g = 0,
        int b = 0,
        int a = 255,
        float duration = DRAW_TIME_DEFAULT);