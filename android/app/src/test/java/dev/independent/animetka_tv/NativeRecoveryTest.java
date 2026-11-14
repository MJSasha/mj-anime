package dev.independent.animetka_tv;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;
import android.content.pm.*;
import android.view.KeyEvent;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.systemchannels.NavigationChannel;
import java.io.File;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

/** Protect compatibility and update trust boundaries recovered from the retained 1.7.0 binary. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 30, manifest = Config.NONE)
public class NativeRecoveryTest {
    MainActivity activity;
    PackageInfo candidate;
    Method check;
    @Before public void setup() throws Exception {
        activity = mock(MainActivity.class, CALLS_REAL_METHODS);
        PackageManager manager = mock(PackageManager.class);
        doReturn(manager).when(activity).getPackageManager();
        doReturn("dev.independent.animetka_tv").when(activity).getPackageName();
        PackageInfo current = info(16, new byte[]{1,2,3});
        candidate = info(17, new byte[]{1,2,3});
        when(manager.getPackageInfo(anyString(), anyInt())).thenReturn(current);
        when(manager.getPackageArchiveInfo(anyString(), anyInt())).thenReturn(candidate);
        check = MainActivity.class.getDeclaredMethod("checkUpdate", File.class);
        check.setAccessible(true);
    }
    PackageInfo info(int version, byte[] certificate) {
        PackageInfo p = new PackageInfo();
        p.packageName = "dev.independent.animetka_tv";
        p.versionCode = version;
        p.signingInfo = mock(SigningInfo.class);
        when(p.signingInfo.getApkContentsSigners()).thenReturn(new Signature[]{new Signature(certificate)});
        return p;
    }
    void reject(String message) throws Exception {
        try { check.invoke(activity, new File("synthetic-update.apk")); fail("Update should be rejected"); }
        catch (InvocationTargetException error) {
            assertTrue(error.getCause() instanceof IllegalStateException);
            assertEquals(message, error.getCause().getMessage());
        }
    }
    @Test public void acceptsOnlyNewerMatchingPackageAndCertificate() throws Exception {
        check.invoke(activity, new File("synthetic-update.apk"));
    }
    @Test public void rejectsNonApk() throws Exception {
        when(activity.getPackageManager().getPackageArchiveInfo(anyString(), anyInt())).thenReturn(null);
        reject("Файл не является APK");
    }
    @Test public void rejectsDifferentPackage() throws Exception {
        candidate.packageName = "other.application";
        reject("Этот APK предназначен для другого приложения");
    }
    @Test public void rejectsSameVersion() throws Exception {
        candidate.versionCode = 16;
        reject("Выберите более новую версию приложения");
    }
    @Test public void rejectsOlderVersion() throws Exception {
        candidate.versionCode = 15;
        reject("Выберите более новую версию приложения");
    }
    @Test public void rejectsDifferentCertificate() throws Exception {
        when(candidate.signingInfo.getApkContentsSigners()).thenReturn(new Signature[]{new Signature(new byte[]{9})});
        reject("Подпись обновления не совпадает");
    }
    @Test public void rejectsMissingCertificate() throws Exception {
        when(candidate.signingInfo.getApkContentsSigners()).thenReturn(new Signature[0]);
        reject("Подпись обновления не совпадает");
    }
    @Test public void backPairPopsExactlyOnce() {
        FlutterEngine engine = mock(FlutterEngine.class);
        NavigationChannel navigation = mock(NavigationChannel.class);
        activity = mock(MainActivity.class, invocation -> {
            if (invocation.getMethod().getName().equals("getFlutterEngine")) return engine;
            return CALLS_REAL_METHODS.answer(invocation);
        });
        when(engine.getNavigationChannel()).thenReturn(navigation);
        assertTrue(activity.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK)));
        verify(navigation, never()).popRoute();
        assertTrue(activity.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BACK)));
        verify(navigation, times(1)).popRoute();
    }
}
