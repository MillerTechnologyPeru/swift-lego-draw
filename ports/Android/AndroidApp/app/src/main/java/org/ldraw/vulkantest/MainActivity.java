package org.ldraw.vulkantest;

import android.app.Activity;
import android.content.res.AssetManager;
import android.os.Bundle;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Loads libLDrawVulkanAndroid.so (built by the sibling Swift package, staged into
 * src/main/jniLibs/ by scripts/stage-jnilibs.sh), extracts the bundled LDraw test model + compiled
 * SPIR-V shaders from the APK's assets/ to internal storage, then forwards this SurfaceView's
 * lifecycle to the native side: {@code nativeSurfaceCreated} wraps the {@link Surface} in an
 * {@code ANativeWindow}, builds a Vulkan swapchain against it, and starts a background render
 * loop that spins the model — no windowing/graphics work happens in Java at all.
 */
public class MainActivity extends Activity implements SurfaceHolder.Callback {
    static {
        System.loadLibrary("LDrawVulkanAndroid");
    }

    private native void nativeSurfaceCreated(
        Surface surface, String assetDir, String shaderDir, int width, int height);
    private native void nativeSurfaceDestroyed();

    private String ldrawDir;
    private String shaderDir;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        SurfaceView surfaceView = new SurfaceView(this);
        setContentView(surfaceView);
        surfaceView.getHolder().addCallback(this);

        try {
            AssetManager assets = getAssets();
            File ldraw = new File(getFilesDir(), "ldraw");
            File shaders = new File(getFilesDir(), "shaders");
            copyAssetTree(assets, "ldraw", ldraw);
            copyAssetTree(assets, "shaders", shaders);
            ldrawDir = ldraw.getAbsolutePath();
            shaderDir = shaders.getAbsolutePath();
        } catch (IOException e) {
            throw new RuntimeException("failed to extract bundled assets", e);
        }
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        // Real width/height come in via surfaceChanged, immediately after this — swapchain
        // creation there has valid dimensions to work with.
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        nativeSurfaceCreated(holder.getSurface(), ldrawDir, shaderDir, width, height);
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        nativeSurfaceDestroyed();
    }

    private void copyAssetTree(AssetManager assets, String assetPath, File dest) throws IOException {
        String[] children = assets.list(assetPath);
        if (children == null || children.length == 0) {
            // Leaf file (list() returns empty for files, non-empty for directories).
            dest.getParentFile().mkdirs();
            try (InputStream in = assets.open(assetPath);
                 OutputStream out = new FileOutputStream(dest)) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                }
            }
            return;
        }
        dest.mkdirs();
        for (String child : children) {
            copyAssetTree(assets, assetPath + "/" + child, new File(dest, child));
        }
    }
}
