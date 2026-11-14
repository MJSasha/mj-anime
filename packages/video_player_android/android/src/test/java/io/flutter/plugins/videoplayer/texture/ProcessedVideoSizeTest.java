package io.flutter.plugins.videoplayer.texture;
import static org.mockito.Mockito.*;
import androidx.media3.common.Format;
import androidx.media3.common.VideoSize;
import androidx.media3.common.util.Size;
import androidx.media3.exoplayer.ExoPlayer;
import io.flutter.plugins.videoplayer.VideoPlayerCallbacks;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=30, manifest=Config.NONE)
public class ProcessedVideoSizeTest {
  @Test public void readyBeforeVideoSizeUsesProcessedTextureDimensions() {
    ExoPlayer exo=mock(ExoPlayer.class); VideoPlayerCallbacks events=mock(VideoPlayerCallbacks.class);
    when(exo.getVideoSize()).thenReturn(VideoSize.UNKNOWN); when(exo.getDuration()).thenReturn(12000L);
    var listener=new TextureExoPlayerEventListener(exo,events,false,()->new Size(1920,1080));
    listener.sendInitialized();
    verify(events).onInitialized(1920,1080,12000L,0);
    verify(events,never()).onInitialized(eq(0),anyInt(),anyLong(),anyInt());
  }
  @Test public void unknownVideoSizeFallsBackToSourceFormatForNormalPlayback() {
    ExoPlayer exo=mock(ExoPlayer.class); VideoPlayerCallbacks events=mock(VideoPlayerCallbacks.class);
    when(exo.getVideoSize()).thenReturn(VideoSize.UNKNOWN); when(exo.getDuration()).thenReturn(12000L);
    when(exo.getVideoFormat()).thenReturn(new Format.Builder().setWidth(640).setHeight(360).build());
    var listener=new TextureExoPlayerEventListener(exo,events,true);
    listener.sendInitialized();
    verify(events).onInitialized(640,360,12000L,0);
  }
  @Test public void missingDimensionsWaitForSizeCallbackAndInitializeOnlyOnce() {
    ExoPlayer exo=mock(ExoPlayer.class); VideoPlayerCallbacks events=mock(VideoPlayerCallbacks.class);
    when(exo.getVideoSize()).thenReturn(VideoSize.UNKNOWN); when(exo.getDuration()).thenReturn(12000L);
    var listener=new TextureExoPlayerEventListener(exo,events,true);
    listener.sendInitialized();
    verify(events,never()).onInitialized(anyInt(),anyInt(),anyLong(),anyInt());
    listener.onVideoSizeChanged(new VideoSize(640,360));
    listener.onVideoSizeChanged(new VideoSize(640,360));
    verify(events,times(1)).onInitialized(640,360,12000L,0);
  }
}
