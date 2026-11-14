package io.flutter.plugins.videoplayer;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;
import android.os.Looper;
import android.view.Surface;
import androidx.media3.common.MediaItem;
import androidx.media3.common.Player;
import androidx.media3.common.util.Size;
import androidx.media3.exoplayer.ExoPlayer;
import io.flutter.plugins.videoplayer.texture.TextureVideoPlayer;
import io.flutter.view.TextureRegistry.SurfaceProducer;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;

/** JVM regression for the Android Surface lifecycle; no emulator, device or video server. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 30, manifest = Config.NONE)
public class UpscaleSurfaceTest {
  ExoPlayer exo;
  SurfaceProducer producer;
  Surface initial, fhd, fourByThree;
  AtomicInteger width, height;
  List<Player.Listener> listeners;
  List<String> failures;
  VideoPlayerOptions options;
  TextureVideoPlayer player;
  @Before public void setup() {
    exo = mock(ExoPlayer.class); producer = mock(SurfaceProducer.class);
    initial = mock(Surface.class); fhd = mock(Surface.class); fourByThree = mock(Surface.class);
    width = new AtomicInteger(1); height = new AtomicInteger(1);
    when(producer.getWidth()).thenAnswer(a -> width.get());
    when(producer.getHeight()).thenAnswer(a -> height.get());
    doAnswer(a -> { width.set(a.getArgument(0)); height.set(a.getArgument(1)); return null; })
        .when(producer).setSize(anyInt(), anyInt());
    when(producer.getSurface()).thenAnswer(a -> width.get() == 1 ? initial : width.get() == 1440 ? fourByThree : fhd);
    listeners = new ArrayList<>(); failures = new ArrayList<>();
    doAnswer(a -> { listeners.add(a.getArgument(0)); return null; }).when(exo).addListener(any());
    options = new VideoPlayerOptions(); options.upscaleMode = 1; options.upscaleFailure = failures::add;
  }
  void create() {
    player = new TextureVideoPlayer(mock(VideoPlayerCallbacks.class), producer, MediaItem.EMPTY, options, () -> exo);
  }
  @Test public void firstBindingUsesResizedSurfaceNotObsoleteOne() {
    create();
    verify(exo, never()).setVideoSurface(initial);
    verify(exo).setVideoSurface(fhd);
    var order = inOrder(producer, exo);
    order.verify(producer).setSize(1920,1080);
    order.verify(producer).getSurface();
    order.verify(exo).setVideoSurface(fhd);
    player.dispose();
  }
  @Test public void sizeChangeAndResumeRebindCurrentSurface() {
    create();
    player.updateUpscaleSurface(new Size(1440,1080));
    verify(exo).setVideoSurface(fourByThree);
    player.onSurfaceCleanup();
    player.onSurfaceAvailable();
    verify(exo, times(2)).setVideoSurface(fourByThree);
    player.dispose();
  }
  @Test public void offKeepsOriginalDecoderSurfaceAndDoesNotAttachEffects() {
    options.upscaleMode = 0; create();
    verify(producer, never()).setSize(anyInt(),anyInt());
    verify(exo, never()).setVideoEffects(anyList());
    verify(exo).setVideoSurface(initial);
    player.dispose();
  }
  @Test public void readyWithoutRenderedFrameReportsFailureOnlyOnce() {
    create(); when(exo.getPlaybackState()).thenReturn(Player.STATE_READY);
    listeners.get(0).onPlaybackStateChanged(Player.STATE_READY);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(9));
    assertEquals(1, failures.size());
    listeners.get(0).onPlaybackStateChanged(Player.STATE_READY);
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(9));
    assertEquals(1, failures.size());
    player.dispose();
  }
  @Test public void renderedFrameOrSurfaceCleanupCancelsWatchdog() {
    create(); when(exo.getPlaybackState()).thenReturn(Player.STATE_READY);
    listeners.get(0).onPlaybackStateChanged(Player.STATE_READY);
    listeners.get(0).onRenderedFirstFrame();
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(9));
    assertTrue(failures.isEmpty());
    player.updateUpscaleSurface(new Size(1440,1080));
    player.onSurfaceCleanup();
    Shadows.shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(9));
    assertTrue(failures.isEmpty());
    player.dispose();
  }
}
