precision highp float;
varying vec2 vTexCoord;
uniform sampler2D u0;
void main() { gl_FragColor = texture2D(u0, vTexCoord); }
