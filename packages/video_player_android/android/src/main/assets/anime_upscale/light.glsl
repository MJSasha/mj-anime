precision highp float;
varying vec2 vTexCoord;
// ImageFilter supplies the input size and sampler without CPU frame readback.
uniform vec2 uStep;
uniform float uStrength;
uniform sampler2D u0;

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
void main() {
  vec2 uv = vTexCoord;

  vec2 lo = 0.5 * uStep;
  vec2 hi = vec2(1.0) - lo;
  vec4 c = texture2D(u0, clamp(uv, lo, hi));
  vec4 n = texture2D(u0, clamp(uv - vec2(0.0, uStep.y), lo, hi));
  vec4 s = texture2D(u0, clamp(uv + vec2(0.0, uStep.y), lo, hi));
  vec4 e = texture2D(u0, clamp(uv + vec2(uStep.x, 0.0), lo, hi));
  vec4 w = texture2D(u0, clamp(uv - vec2(uStep.x, 0.0), lo, hi));
  // Leave transparent letterbox boundaries untouched.
  float alpha = min(c.a, min(min(n.a, s.a), min(e.a, w.a)));
  if (alpha < 0.99) { gl_FragColor = c; return; }
  float y = luma(c.rgb);
  vec4 neighbors = vec4(luma(n.rgb), luma(s.rgb), luma(e.rgb), luma(w.rgb));
  float ymin = min(y, min(min(neighbors.x, neighbors.y), min(neighbors.z, neighbors.w)));
  float ymax = max(y, max(max(neighbors.x, neighbors.y), max(neighbors.z, neighbors.w)));
  float range = ymax - ymin;
  float mean = dot(neighbors, vec4(0.25));
  // Ignore low-contrast compression noise. Luma-only sharpening keeps anime colours.
  float gate = smoothstep(0.018, 0.075, range);
  float limit = min(0.022, range * 0.12);
  float detail = clamp((y - mean) * uStrength * gate, -limit, limit);
  // Local extrema clamp prevents bright/dark halos on inked contours.
  float adjusted = clamp(y + detail, ymin, ymax);
  gl_FragColor = vec4(clamp(c.rgb + vec3(adjusted - y), 0.0, 1.0), c.a);
}
