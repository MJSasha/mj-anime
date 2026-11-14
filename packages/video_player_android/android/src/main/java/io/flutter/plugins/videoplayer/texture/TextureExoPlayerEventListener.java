// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer.texture;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.media3.common.Format;
import androidx.media3.common.VideoSize;
import androidx.media3.exoplayer.ExoPlayer;
import io.flutter.plugins.videoplayer.ExoPlayerEventListener;
import io.flutter.plugins.videoplayer.VideoPlayerCallbacks;

public final class TextureExoPlayerEventListener extends ExoPlayerEventListener {
  private final boolean surfaceProducerHandlesCropAndRotation;
  @Nullable private final java.util.function.Supplier<androidx.media3.common.util.Size> processedSize;
  private boolean waitingForSize;
  @Nullable private VideoSize pendingSize;

  public TextureExoPlayerEventListener(
      @NonNull ExoPlayer exoPlayer,
      @NonNull VideoPlayerCallbacks events,
      boolean surfaceProducerHandlesCropAndRotation) {
    this(exoPlayer, events, surfaceProducerHandlesCropAndRotation, null);
  }

  public TextureExoPlayerEventListener(ExoPlayer exoPlayer, VideoPlayerCallbacks events,
      boolean surfaceProducerHandlesCropAndRotation,
      @Nullable java.util.function.Supplier<androidx.media3.common.util.Size> processedSize) {
    super(exoPlayer, events);
    this.surfaceProducerHandlesCropAndRotation = surfaceProducerHandlesCropAndRotation;
    this.processedSize = processedSize;
  }

  @Override public void onVideoSizeChanged(VideoSize size) {
    pendingSize = size;
    if (waitingForSize && size.width > 0 && size.height > 0) sendInitialized();
  }

  @Override public void onTracksChanged(androidx.media3.common.Tracks tracks) {
    super.onTracksChanged(tracks);
    if (waitingForSize && exoPlayer.getVideoFormat() != null) sendInitialized();
  }

  @Override
  protected void sendInitialized() {
    VideoSize videoSize = exoPlayer.getVideoSize();
    RotationDegrees rotationCorrection = RotationDegrees.ROTATE_0;
    int width = videoSize.width;
    int height = videoSize.height;
    float pixelWidthHeightRatio = videoSize.pixelWidthHeightRatio;
    // With custom Media3 GL effects STATE_READY may precede video-size reporting.
    // Never initialize Flutter with 0x0: it would render a valid texture at zero size.
    if (width <= 0 || height <= 0) {
      if (processedSize != null) {
        androidx.media3.common.util.Size size = processedSize.get();
        width = size.getWidth(); height = size.getHeight();
        pixelWidthHeightRatio = 1f;
      } else if (pendingSize != null && pendingSize.width > 0 && pendingSize.height > 0) {
        width = pendingSize.width; height = pendingSize.height;
        pixelWidthHeightRatio = pendingSize.pixelWidthHeightRatio;
      } else {
        Format format = exoPlayer.getVideoFormat();
        if (format != null) { width = format.width; height = format.height; pixelWidthHeightRatio = format.pixelWidthHeightRatio; }
      }
    }
    if (width <= 0 || height <= 0) { waitingForSize = true; return; }
    waitingForSize = false;
    android.util.Log.i("MJAnimeVideo", "Initialized visible texture " + width + "x" + height);
    if (width != 0 && height != 0) {
      // Anamorphic content is stored with non-square pixels, so the coded width has to be
      // scaled by the pixel aspect ratio to obtain the display width. ExoPlayer reports a
      // pixelWidthHeightRatio that already accounts for any applied rotation, so this is
      // correct regardless of the rotation correction computed below.
      // Clamped to at least one pixel so that a malformed ratio cannot report a zero width.
      if (pixelWidthHeightRatio > 0 && pixelWidthHeightRatio != 1f) {
        width = Math.max(1, Math.round(width * pixelWidthHeightRatio));
      }

      // When the SurfaceTexture backend for Impeller is used, the preview should already
      // be correctly rotated.
      if (!surfaceProducerHandlesCropAndRotation) {
        // The video's Format also provides a rotation correction that may be used to
        // correct the rotation, so we try to use that to correct the video rotation
        // when the ImageReader backend for Impeller is used.
        int rawVideoFormatRotation = getRotationCorrectionFromFormat(exoPlayer);

        try {
          rotationCorrection = RotationDegrees.fromDegrees(rawVideoFormatRotation);
        } catch (IllegalArgumentException e) {
          // Rotation correction other than 0, 90, 180, 270 reported by Format. Because this is
          // unexpected we apply no rotation correction.
          rotationCorrection = RotationDegrees.ROTATE_0;
        }
      }
    }
    events.onInitialized(width, height, exoPlayer.getDuration(), rotationCorrection.getDegrees());
  }

  @OptIn(markerClass = androidx.media3.common.util.UnstableApi.class)
  // A video's Format and its rotation degrees are unstable because they are not guaranteed
  // the same implementation across API versions. It is possible that this logic may need
  // revisiting should the implementation change across versions of the Exoplayer API.
  private int getRotationCorrectionFromFormat(ExoPlayer exoPlayer) {
    Format videoFormat = exoPlayer.getVideoFormat();
    return videoFormat == null ? 0 : videoFormat.rotationDegrees;
  }
}
