#version 460 core

// Player backdrop flowing-light layer.
//
// Four soft color bodies drift along Lissajous orbits, each breathing on its
// own cycle. Composited over the existing static blurred-artwork backdrop, so
// this shader only contributes the moving color — everything it leaves
// transparent shows the layer underneath.
//
// Two things carry the sense of motion, and both are about *spatial variation*
// rather than speed:
//   - Coverage must not saturate. An earlier version clamped the summed
//     falloff to 1.0, which pinned alpha at full across most of the screen and
//     rendered a flat slab that looked frozen no matter how fast it moved.
//     The soft exponential below keeps alpha varying across the frame.
//   - Bodies must be small enough to leave gaps. Radii near the short side
//     made every pixel a mix of all four, averaging out to one constant color.
//
// Cost note: one full-screen pass, no blur, no saveLayer. ~50 ALU ops per
// fragment at a single overdraw layer.

#include <flutter/runtime_effect.glsl>

// Viewport size in logical pixels.
uniform vec2 uSize;
// Loop phase in 0..1. Every temporal frequency below is an integer multiple,
// so the composition is seamless across the wrap and never jumps.
uniform float uTime;
// Ceiling on the layer's opacity. Set from the theme brightness — it is what
// keeps lyric contrast intact, so it must stay bounded.
uniform float uIntensity;
// rgb = body color (0..1), w = body radius in short-side units.
uniform vec4 uBody0;
uniform vec4 uBody1;
uniform vec4 uBody2;
uniform vec4 uBody3;

out vec4 fragColor;

const float kTau = 6.28318530718;

// Orbit origins are authored in normalized uv and scaled by the viewport
// aspect so they spread across the whole screen. Amplitudes deliberately are
// NOT scaled: keeping them in short-side units makes each body travel a
// roughly circular path instead of one stretched by the screen ratio.
vec2 orbit(vec2 origin, vec2 amplitude, vec2 freq, float phase, float t) {
  return origin + amplitude * vec2(sin(kTau * (t * freq.x + phase)),
                                   cos(kTau * (t * freq.y + phase)));
}

// Quadratic falloff to zero at the radius. Squaring softens the rim so the
// bodies read as light rather than as circles.
float body(vec2 p, vec2 center, float radius) {
  float d = length(p - center) / radius;
  float f = max(0.0, 1.0 - d * d);
  return f * f;
}

// Per-body brightness breathing. Without this the bodies only translate, and
// pure translation of a soft gradient is nearly invisible.
float pulse(float freq, float phase, float t) {
  return 0.68 + 0.32 * sin(kTau * (t * freq + phase));
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;

  // Work in short-side units so the bodies stay circular instead of being
  // stretched by the viewport ratio.
  vec2 aspect = uSize / min(uSize.x, uSize.y);
  vec2 p = uv * aspect;

  float t = uTime;

  // Low-frequency domain warp: bends the body outlines so they stop reading
  // as ellipses. Integer time frequencies keep the loop seamless.
  p += 0.14 * vec2(sin(p.y * 2.1 + kTau * t),
                   cos(p.x * 1.7 - kTau * 2.0 * t));

  // Origins stay clustered toward the vertical middle. On a tall phone the
  // aspect scale spreads them far apart, and a wider spread would drop the
  // screen centre — where the lyrics sit — into the gap between two bodies.
  vec2 c0 = orbit(vec2(0.28, 0.26) * aspect, vec2(0.26, 0.22),
                  vec2(1.0, 2.0), 0.00, t);
  vec2 c1 = orbit(vec2(0.74, 0.44) * aspect, vec2(0.22, 0.26),
                  vec2(2.0, 3.0), 0.37, t);
  vec2 c2 = orbit(vec2(0.30, 0.62) * aspect, vec2(0.28, 0.20),
                  vec2(3.0, 1.0), 0.61, t);
  vec2 c3 = orbit(vec2(0.70, 0.80) * aspect, vec2(0.20, 0.24),
                  vec2(1.0, 3.0), 0.19, t);

  float f0 = body(p, c0, uBody0.w) * pulse(1.0, 0.00, t);
  float f1 = body(p, c1, uBody1.w) * pulse(2.0, 0.41, t);
  float f2 = body(p, c2, uBody2.w) * pulse(1.0, 0.73, t);
  float f3 = body(p, c3, uBody3.w) * pulse(2.0, 0.22, t);

  float cover = f0 + f1 + f2 + f3;
  if (cover <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }

  // Hue comes from the weighted mean so overlaps mix instead of clipping.
  vec3 rgb = (uBody0.rgb * f0 + uBody1.rgb * f1 +
              uBody2.rgb * f2 + uBody3.rgb * f3) / cover;

  // Lift the dominant body's core and let the rims fall off darker. This is
  // the luminance contrast that makes the field read as flowing light rather
  // than as a tinted sheet.
  float core = max(max(f0, f1), max(f2, f3));
  rgb *= 0.78 + 0.50 * core;

  // Soft saturation instead of clamp: alpha keeps varying across the frame
  // even where several bodies overlap.
  float alpha = (1.0 - exp(-cover * 1.7)) * uIntensity;

  // Flutter expects premultiplied alpha.
  fragColor = vec4(rgb * alpha, alpha);
}
