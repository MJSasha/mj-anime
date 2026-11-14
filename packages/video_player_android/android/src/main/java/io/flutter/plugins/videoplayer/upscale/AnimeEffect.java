package io.flutter.plugins.videoplayer.upscale;

import android.content.Context;
import android.opengl.GLES20;
import android.opengl.GLES30;
import androidx.media3.common.VideoFrameProcessingException;
import androidx.media3.common.util.GlProgram;
import androidx.media3.common.util.GlUtil;
import androidx.media3.common.util.Size;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.effect.BaseGlShaderProgram;
import androidx.media3.effect.GlEffect;
import androidx.media3.effect.GlShaderProgram;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.function.Consumer;
import org.json.JSONArray;
import org.json.JSONObject;

/** MJAnime: one-pass contour filter or real Anime4K S/M CNN, entirely on the GPU. */
@UnstableApi
public final class AnimeEffect implements GlEffect {
  private final int mode;
  private final Consumer<Size> outputSize;
  private final Consumer<String> status;
  public AnimeEffect(int mode, Consumer<Size> outputSize, Consumer<String> status) {
    this.mode = mode;
    this.outputSize = outputSize;
    this.status = status;
  }
  @Override
  public GlShaderProgram toGlShaderProgram(Context context, boolean useHdr)
      throws VideoFrameProcessingException {
    return new Program(context, useHdr, mode, outputSize, status);
  }
  static String asset(Context context, String file) throws Exception {
    try (InputStream in = context.getAssets().open(file);
         ByteArrayOutputStream out = new ByteArrayOutputStream()) {
      byte[] buffer = new byte[8192];
      for (int n; (n = in.read(buffer)) != -1;) out.write(buffer, 0, n);
      return out.toString(StandardCharsets.UTF_8.name());
    }
  }
  private static final class Program extends BaseGlShaderProgram {
    private static final float[] QUAD = {-1,-1, 1,-1, -1,1, 1,1};
    private final Context context;
    private final boolean hdr;
    private final int requested;
    private final Consumer<Size> outputSize;
    private final Consumer<String> status;
    private final GlProgram copy, light;
    private final String vertex;
    private final List<GlProgram> cnn = new ArrayList<>();
    private final List<int[]> inputs = new ArrayList<>();
    private final List<Integer> textures = new ArrayList<>(), fbos = new ArrayList<>();
    private final HashSet<Integer> floatingTextures = new HashSet<>();
    private int width, height, outWidth, outHeight, active;

    Program(Context context, boolean hdr, int mode, Consumer<Size> outputSize,
            Consumer<String> status) throws VideoFrameProcessingException {
      super(hdr, 1);
      this.context = context; this.hdr = hdr; requested = mode;
      this.outputSize = outputSize; this.status = status;
      try {
        vertex = asset(context, "anime_upscale/vertex.glsl");
        copy = program("anime_upscale/copy.glsl");
        light = program("anime_upscale/light.glsl");
      } catch (Exception e) { throw new VideoFrameProcessingException(e); }
    }
    private GlProgram program(String file) throws Exception {
      GlProgram p = new GlProgram(vertex, asset(context, file));
      p.setBufferAttribute("aPosition", QUAD, 2);
      return p;
    }
    @Override
    public Size configure(int inputWidth, int inputHeight) throws VideoFrameProcessingException {
      width = inputWidth; height = inputHeight;
      float scale = Math.min(1920f / width, 1080f / height);
      outWidth = Math.max(2, Math.round(width * scale));
      outHeight = Math.max(2, Math.round(height * scale));
      active = hdr ? 0 : requested;
      String reason = "";
      try {
        releaseCnn();
        if (active >= 2 && scale <= 1.2f) {
          active = 1;
          reason = " · исходник близок к Full HD, применяется лёгкий фильтр";
        }
        if (active >= 2) {
          try { configureCnn(); }
          catch (Exception unsupported) {
            releaseCnn(); active = 1;
            reason = " · CNN недоступна на GPU, применяется лёгкий фильтр";
          }
        }
        if (hdr) reason = " · HDR без обработки";
        outputSize.accept(new Size(outWidth, outHeight));
        status.accept((active == 0 ? "Обычное изображение" : active == 1 ? "Лёгкий" : active == 2 ? "Anime4K CNN S" : "Anime4K CNN M")
            + " · " + width + "×" + height + " → " + outWidth + "×" + outHeight + reason);
        return new Size(outWidth, outHeight);
      } catch (Exception e) { throw new VideoFrameProcessingException(e); }
    }
    private void configureCnn() throws Exception {
      String prefix = "anime_upscale/cnn_" + (active == 2 ? "s" : "m") + "/";
      JSONArray manifest = new JSONArray(asset(context, prefix + "manifest.json"));
      for (int i = 0; i < manifest.length(); i++) {
        JSONObject pass = manifest.getJSONObject(i);
        cnn.add(program(pass.getString("file")));
        JSONArray refs = pass.getJSONArray("inputs");
        int[] ids = new int[refs.length()];
        for (int j = 0; j < ids.length; j++) ids[j] = refs.getInt(j);
        inputs.add(ids);
        boolean last = i == manifest.length() - 1;
        if (active == 2 && i >= 2 && !last) {
          // S has no skip connections: two signed FP16 feature maps suffice.
          textures.add(textures.get(i % 2)); fbos.add(fbos.get(i % 2));
        } else {
          int tex = texture(last ? width * 2 : width, last ? height * 2 : height, !last);
          textures.add(tex);
          if (!last) floatingTextures.add(tex);
          int fbo = GlUtil.createFboForTexture(tex); fbos.add(fbo);
          GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo);
          if (GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER) != GLES20.GL_FRAMEBUFFER_COMPLETE)
            throw new IllegalStateException("Signed FP16 rendering is unavailable");
        }
      }
    }
    private int texture(int w, int h, boolean floating) throws GlUtil.GlException {
      if (!floating) return GlUtil.createTexture(w, h, false);
      int[] id = new int[1]; GLES20.glGenTextures(1, id, 0);
      GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id[0]);
      GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_NEAREST);
      GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST);
      GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
      GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);
      String version = GLES20.glGetString(GLES20.GL_VERSION);
      if (version != null && version.contains("OpenGL ES 3")) {
        GLES30.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES30.GL_RGBA16F, w, h, 0,
            GLES20.GL_RGBA, GLES30.GL_HALF_FLOAT, null);
      } else {
        GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, w, h, 0,
            GLES20.GL_RGBA, 0x8D61 /* GL_HALF_FLOAT_OES */, null);
      }
      try { GlUtil.checkGlError(); }
      catch (GlUtil.GlException e) { GLES20.glDeleteTextures(1, id, 0); throw e; }
      return id[0];
    }
    private void draw(GlProgram p, int[] texIds) throws GlUtil.GlException {
      p.use();
      p.setFloatsUniformIfPresent("uStep", new float[] {1f/width, 1f/height});
      p.setFloatsUniformIfPresent("uInputSize", new float[] {width, height});
      p.setFloatsUniformIfPresent("uStrength", new float[] {height < 1080 ? .32f : .18f});
      for (int i = 0; i < texIds.length; i++) p.setSamplerTexIdUniform("u" + i, texIds[i], i);
      p.bindAttributesAndUniforms();
      // Media3's sampler binding sets LINEAR. Signed half-float feature maps must
      // stay NEAREST, including on ES2 devices without half-float-linear filtering.
      for (int i = 0; i < texIds.length; i++) {
        if (floatingTextures.contains(texIds[i])) {
          GLES20.glActiveTexture(GLES20.GL_TEXTURE0+i);
          GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D,GLES20.GL_TEXTURE_MIN_FILTER,GLES20.GL_NEAREST);
          GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D,GLES20.GL_TEXTURE_MAG_FILTER,GLES20.GL_NEAREST);
        }
      }
      GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
      GlUtil.checkGlError();
    }
    @Override
    public void drawFrame(int inputTexId, long presentationTimeUs) throws VideoFrameProcessingException {
      try {
        GLES20.glDisable(GLES20.GL_BLEND);
        GLES20.glDisable(GLES20.GL_SCISSOR_TEST);
        int[] output = new int[1];
        GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, output, 0);
        if (active >= 2) {
          for (int i = 0; i < cnn.size(); i++) {
            boolean last = i == cnn.size() - 1;
            GlUtil.focusFramebufferUsingCurrentContext(fbos.get(i), last ? width*2 : width, last ? height*2 : height);
            int[] refs = inputs.get(i), samplers = new int[refs.length];
            for (int j = 0; j < refs.length; j++) samplers[j] = refs[j] < 0 ? inputTexId : textures.get(refs[j]);
            draw(cnn.get(i), samplers);
          }
          GlUtil.focusFramebufferUsingCurrentContext(output[0], outWidth, outHeight);
          draw(copy, new int[] {textures.get(textures.size()-1)});
        } else {
          GlUtil.focusFramebufferUsingCurrentContext(output[0], outWidth, outHeight);
          draw(active == 1 ? light : copy, new int[] {inputTexId});
        }
      } catch (Exception e) { throw new VideoFrameProcessingException(e); }
    }
    private void releaseCnn() throws GlUtil.GlException {
      for (GlProgram p : cnn) p.delete();
      cnn.clear(); inputs.clear();
      for (int fbo : new HashSet<>(fbos)) GLES20.glDeleteFramebuffers(1, new int[]{fbo}, 0);
      for (int tex : new HashSet<>(textures)) GLES20.glDeleteTextures(1, new int[]{tex}, 0);
      fbos.clear(); textures.clear(); floatingTextures.clear();
    }
    @Override
    public void release() throws VideoFrameProcessingException {
      try { releaseCnn(); copy.delete(); light.delete(); }
      catch (GlUtil.GlException e) { throw new VideoFrameProcessingException(e); }
      finally { super.release(); }
    }
  }
}
