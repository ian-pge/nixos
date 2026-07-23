#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float phase;
};

const float PI = 3.14159265358979323846;
const float OUTER_RADIUS = 18.0;
const float BORDER_WIDTH = 2.0;
const float TRAIL_LENGTH = 0.5;
const vec3 TRAIL_COLOR = vec3(1.0, 0.2, 0.8);

float roundedRectSdf(vec2 point, vec2 size, float radius)
{
    vec2 halfSize = size * 0.5;
    vec2 q = abs(point - halfSize) - (halfSize - vec2(radius));
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

float roundedRectPosition(vec2 point, vec2 size, float radius)
{
    float horizontal = max(0.0, size.x - radius * 2.0);
    float vertical = max(0.0, size.y - radius * 2.0);
    float arc = PI * radius * 0.5;
    float perimeter = max(1.0,
        horizontal * 2.0 + vertical * 2.0 + arc * 4.0);
    float right = size.x - radius;
    float bottom = size.y - radius;
    float distance = 0.0;

    if (point.y <= radius) {
        if (point.x < radius) {
            float angle = atan(point.y - radius, point.x - radius);
            if (angle < 0.0)
                angle += PI * 2.0;
            distance = horizontal * 2.0 + vertical * 2.0 + arc * 3.0
                + (angle - PI) * radius;
        } else if (point.x > right) {
            float angle = atan(point.y - radius, point.x - right);
            distance = horizontal + (angle + PI * 0.5) * radius;
        } else {
            distance = point.x - radius;
        }
    } else if (point.y >= bottom) {
        if (point.x > right) {
            float angle = atan(point.y - bottom, point.x - right);
            distance = horizontal + vertical + arc + angle * radius;
        } else if (point.x < radius) {
            float angle = atan(point.y - bottom, point.x - radius);
            distance = horizontal * 2.0 + vertical + arc * 2.0
                + (angle - PI * 0.5) * radius;
        } else {
            distance = horizontal + vertical + arc * 2.0
                + (right - point.x);
        }
    } else if (point.x >= right) {
        distance = horizontal + arc + (point.y - radius);
    } else if (point.x <= radius) {
        distance = horizontal * 2.0 + vertical + arc * 3.0
            + (bottom - point.y);
    }

    return fract(distance / perimeter);
}

void main()
{
    vec2 size = max(itemSize, vec2(1.0));
    vec2 point = qt_TexCoord0 * size;
    float radius = min(OUTER_RADIUS, min(size.x, size.y) * 0.5);
    float sdf = roundedRectSdf(point, size, radius);
    float halfBorder = BORDER_WIDTH * 0.5;
    float antialias = max(fwidth(sdf), 0.35);
    float borderAlpha = 1.0 - smoothstep(
        halfBorder - antialias,
        halfBorder + antialias,
        abs(sdf + halfBorder)
    );

    float centerInset = halfBorder;
    vec2 centerSize = max(vec2(1.0),
        size - vec2(centerInset * 2.0));
    float centerRadius = max(0.001, radius - centerInset);
    float position = roundedRectPosition(
        point - vec2(centerInset), centerSize, centerRadius);
    float behindHead = fract(phase - position);
    float trailAlpha = behindHead <= TRAIL_LENGTH
        ? pow(1.0 - behindHead / TRAIL_LENGTH, 1.35)
        : 0.0;

    float alpha = borderAlpha * trailAlpha * qt_Opacity;
    fragColor = vec4(TRAIL_COLOR * alpha, alpha);
}
