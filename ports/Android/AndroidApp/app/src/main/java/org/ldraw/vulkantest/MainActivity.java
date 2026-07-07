package org.ldraw.vulkantest;

import android.app.Activity;
import android.content.res.AssetManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.TextView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Loads libLDrawVulkanAndroid.so (built by the sibling Swift package, staged into
 * src/main/jniLibs/ by scripts/stage-jnilibs.sh), extracts the bundled LDraw test model from the
 * APK's assets/ to internal storage (the NDK's AAssetManager isn't a plain filesystem path, but
 * the Swift side just wants a directory it can read with String(contentsOf:)), then calls the
 * exported {@code runVulkanTest} native method on a background thread — it runs a real Vulkan
 * render + GPU readback, so it must not block the UI thread.
 */
public class MainActivity extends Activity {
    private static final String TAG = "LDrawVulkanTest";

    static {
        System.loadLibrary("LDrawVulkanAndroid");
    }

    private native String runVulkanTest(String assetDir, String outputPath, int width, int height);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        TextView statusText = findViewById(R.id.statusText);
        Handler mainHandler = new Handler(Looper.getMainLooper());

        new Thread(() -> {
            String resultMessage;
            try {
                String assetDir = extractBundledAssets();
                String outputPath = new File(getFilesDir(), "output.ppm").getAbsolutePath();
                resultMessage = runVulkanTest(assetDir, outputPath, 800, 600);
            } catch (IOException e) {
                resultMessage = "FAIL: asset extraction error: " + e;
            }
            Log.i(TAG, resultMessage);
            String finalMessage = resultMessage;
            mainHandler.post(() -> statusText.setText(finalMessage));
        }).start();
    }

    /**
     * Copies assets/ldraw/** (the 2x4 brick + its stud/box primitives — same files the iOS
     * playground bundles) into {@code <internal storage>/ldraw/}, returning that directory's
     * path. Runs on every launch; the model is a handful of tiny text files so re-copying is
     * effectively free.
     */
    private String extractBundledAssets() throws IOException {
        File destRoot = new File(getFilesDir(), "ldraw");
        AssetManager assets = getAssets();
        copyAssetTree(assets, "ldraw", destRoot);
        return destRoot.getAbsolutePath();
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
