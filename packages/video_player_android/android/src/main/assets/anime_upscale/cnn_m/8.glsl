precision highp float;
varying vec2 vTexCoord;
uniform vec2 uStep;
uniform vec2 uInputSize;
uniform sampler2D u0;
#define MAIN_pos vTexCoord
#define MAIN_size uInputSize
#define MAIN_pt uStep
#define MAIN_tex(pos) texture2D(u0, pos)
#define MAIN_texOff(off) texture2D(u0, vTexCoord + vec2(off) * uStep)
uniform sampler2D u1;
#define conv2d_last_tf_pos vTexCoord
#define conv2d_last_tf_size uInputSize
#define conv2d_last_tf_pt uStep
#define conv2d_last_tf_tex(pos) texture2D(u1, pos)
#define conv2d_last_tf_texOff(off) texture2D(u1, vTexCoord + vec2(off) * uStep)

vec4 hook() {
    vec2 f0 = fract(conv2d_last_tf_pos * conv2d_last_tf_size);
    ivec2 i0 = ivec2(f0 * vec2(2.0));
    vec4 features = conv2d_last_tf_tex((vec2(0.5) - f0) * conv2d_last_tf_pt + conv2d_last_tf_pos);
    float c0 = i0.y == 0 ? (i0.x == 0 ? features.r : features.g) : (i0.x == 0 ? features.b : features.a);
    float c1 = c0;
    float c2 = c1;
    float c3 = c2;
    return vec4(c0, c1, c2, c3) + MAIN_tex(MAIN_pos);
}
void main() { gl_FragColor = vec4(clamp(hook().rgb, 0.0, 1.0), 1.0); }
