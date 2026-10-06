#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Slow, continuous refraction over a pre-blurred thumbnail, in one GPU pass.
[[ stitchable ]] half4 daydreamFlow(float2 position, SwiftUI::Layer layer, float time, float2 size) {
    float2 uv = position / max(size, float2(1.0));
    float breath = 0.5 + 0.5 * sin(time * 0.55);
    float radius = 3.0 + 12.0 * breath;
    float2 drift = float2(sin(uv.y * 7.0 + time * 0.38), cos(uv.x * 6.0 - time * 0.31)) * 8.0;
    float2 p = position + drift;
    half4 colour = layer.sample(p) * 0.24h;
    colour += layer.sample(p + float2(radius, 0)) * 0.12h;
    colour += layer.sample(p - float2(radius, 0)) * 0.12h;
    colour += layer.sample(p + float2(0, radius)) * 0.12h;
    colour += layer.sample(p - float2(0, radius)) * 0.12h;
    colour += layer.sample(p + float2(radius * 0.7, radius * 0.7)) * 0.07h;
    colour += layer.sample(p - float2(radius * 0.7, radius * 0.7)) * 0.07h;
    colour += layer.sample(p + float2(radius * 0.7, -radius * 0.7)) * 0.07h;
    colour += layer.sample(p - float2(radius * 0.7, -radius * 0.7)) * 0.07h;

    float band = pow(0.5 + 0.5 * sin(uv.x * 4.2 + uv.y * 2.8 - time * 0.4), 3.0);
    half3 prism = half3(0.5 + 0.5 * sin(time * 0.22 + uv.y * 3.0),
                       0.5 + 0.5 * sin(time * 0.19 + uv.x * 3.0 + 2.1),
                       0.5 + 0.5 * sin(time * 0.17 + uv.y * 2.0 + 4.2));
    colour.rgb = colour.rgb * 0.78h + prism * half(0.18 + band * 0.18) * colour.a;
    return half4(clamp(colour.rgb, half3(0), half3(colour.a)), colour.a);
}
