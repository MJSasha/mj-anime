package dev.independent.animetka_tv;

import org.junit.Test;
import java.io.*;
import java.util.concurrent.CancellationException;
import static org.junit.Assert.*;

public class ReleaseDownloadTest {
    @Test public void allowsOnlyOwnReleaseAssetsAndGithubHttpsRedirects() {
        ReleaseDownload.INSTANCE.validateUrl("https://github.com/MJSasha/mj-anime/releases/download/v1.8.0/MJAnime-1.8.0.apk", true);
        ReleaseDownload.INSTANCE.validateUrl("https://release-assets.githubusercontent.com/file?token=signed", false);
        for (String value : new String[] {
            "http://github.com/MJSasha/mj-anime/releases/download/v1.8.0/MJAnime-1.8.0.apk",
            "https://github.com/other/repo/releases/download/v1.8.0/MJAnime-1.8.0.apk",
            "https://github.com.evil.example/file", "https://user@github.com/file",
            "https://github.com:443/file", "https://github.com/file#fragment"
        }) {
            assertThrows(Exception.class, () -> ReleaseDownload.INSTANCE.validateUrl(value, true));
        }
        assertThrows(Exception.class, () -> ReleaseDownload.INSTANCE.validateUrl("https://evil.example/file", false));
        assertThrows(Exception.class, () -> ReleaseDownload.INSTANCE.validateUrl("http://release-assets.githubusercontent.com/file", false));
    }
    @Test public void boundsAndHashAreRequired() {
        ReleaseDownload.INSTANCE.validateMetadata(1024, "a".repeat(64));
        assertThrows(Exception.class, () -> ReleaseDownload.INSTANCE.validateMetadata(0, "a".repeat(64)));
        assertThrows(Exception.class, () -> ReleaseDownload.INSTANCE.validateMetadata(134217729, "a".repeat(64)));
        assertThrows(Exception.class, () -> ReleaseDownload.INSTANCE.validateMetadata(1, "bad"));
    }
    @Test public void verifiesStreamAndRejectsCorruptionTruncationOverflowAndCancellation() throws Exception {
        String hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ReleaseDownload.INSTANCE.copyVerified(new ByteArrayInputStream("abc".getBytes()), out, 3, hash, () -> false);
        assertEquals("abc", out.toString());
        for (String data : new String[]{"ab", "abcd", "abd"}) {
            assertThrows(IllegalStateException.class, () -> ReleaseDownload.INSTANCE.copyVerified(
                new ByteArrayInputStream(data.getBytes()), new ByteArrayOutputStream(), 3, hash, () -> false));
        }
        assertThrows(CancellationException.class, () -> ReleaseDownload.INSTANCE.copyVerified(
            new ByteArrayInputStream("abc".getBytes()), new ByteArrayOutputStream(), 3, hash, () -> true));
    }

}
