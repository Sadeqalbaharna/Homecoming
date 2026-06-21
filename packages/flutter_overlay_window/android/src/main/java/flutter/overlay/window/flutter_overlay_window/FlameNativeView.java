package flutter.overlay.window.flutter_overlay_window;

import android.content.Context;
import android.graphics.ImageDecoder;
import android.graphics.drawable.AnimatedImageDrawable;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;

import java.io.IOException;
import java.io.InputStream;

/**
 * Flame overlay view using the custom WebP animation asset.
 * Transparent background — WebP alpha is preserved by ImageDecoder.
 * Drag + tap handled via dispatchTouchEvent (same as before).
 */
public class FlameNativeView extends ImageView {

    // ── Drag state ────────────────────────────────────────────────────────────
    private WindowManager wm;
    private WindowManager.LayoutParams lp;
    private Runnable onTap;
    private Runnable onLongPress;

    private float touchDownX, touchDownY;
    private int   paramDownX, paramDownY;
    private boolean dragging = false;
    private static final int SLOP = 16;         // px — less than this = tap
    private static final int LONG_PRESS_MS = 500;

    private final Handler longPressHandler = new Handler(Looper.getMainLooper());
    private Runnable longPressRunnable;

    private AnimatedImageDrawable animDrawable;

    // ─────────────────────────────────────────────────────────────────────────

    public FlameNativeView(Context ctx) {
        super(ctx);
        setBackground(null);
        setScaleType(ImageView.ScaleType.FIT_CENTER);
        loadFlameAnimation(ctx);
    }

    private void loadFlameAnimation(Context ctx) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                // Load from Android assets (android/app/src/main/assets/)
                ImageDecoder.Source source = ImageDecoder.createSource(
                        ctx.getAssets(), "flame_overlay.webp");
                Drawable drawable = ImageDecoder.decodeDrawable(source, (decoder, info, src) -> {
                    decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
                });
                if (drawable instanceof AnimatedImageDrawable) {
                    animDrawable = (AnimatedImageDrawable) drawable;
                    animDrawable.setRepeatCount(AnimatedImageDrawable.REPEAT_INFINITE);
                    setImageDrawable(animDrawable);
                    animDrawable.start();
                    Log.d("FlameNativeView", "WebP animation loaded and started");
                } else {
                    Log.w("FlameNativeView", "Drawable is not animated: " + drawable.getClass());
                    setImageDrawable(drawable);
                }
            } catch (IOException e) {
                Log.e("FlameNativeView", "Failed to load flame_overlay.webp", e);
            }
        } else {
            // API < 28: fallback — just show nothing (Canvas flame was removed)
            Log.w("FlameNativeView", "API < 28, AnimatedImageDrawable not supported");
        }
    }

    /**
     * Must be called immediately after construction, before addView().
     */
    public void attach(WindowManager windowManager,
                       WindowManager.LayoutParams layoutParams,
                       Runnable tapCallback,
                       Runnable longPressCallback) {
        this.wm          = windowManager;
        this.lp          = layoutParams;
        this.onTap       = tapCallback;
        this.onLongPress = longPressCallback;
    }

    public void setHasPending(boolean pending) {
        // Badge logic can be added later (e.g. overlay a dot drawable)
    }

    // ── Touch ─────────────────────────────────────────────────────────────────

    @Override
    public boolean dispatchTouchEvent(MotionEvent e) {
        switch (e.getAction()) {

            case MotionEvent.ACTION_DOWN:
                touchDownX = e.getRawX();
                touchDownY = e.getRawY();
                paramDownX = lp.x;
                paramDownY = lp.y;
                dragging   = false;
                // Schedule long press
                longPressRunnable = () -> {
                    if (!dragging && onLongPress != null) {
                        onLongPress.run();
                    }
                };
                longPressHandler.postDelayed(longPressRunnable, LONG_PRESS_MS);
                return true;

            case MotionEvent.ACTION_MOVE:
                float dx = e.getRawX() - touchDownX;
                float dy = e.getRawY() - touchDownY;
                if (!dragging && Math.abs(dx) < SLOP && Math.abs(dy) < SLOP) {
                    return true;
                }
                // Cancel long press once drag is confirmed
                if (!dragging) longPressHandler.removeCallbacks(longPressRunnable);
                dragging = true;
                lp.x = paramDownX + (int) dx;
                lp.y = paramDownY + (int) dy;
                if (wm != null) wm.updateViewLayout(this, lp);
                return true;

            case MotionEvent.ACTION_UP:
                longPressHandler.removeCallbacks(longPressRunnable);
                if (!dragging) {
                    if (onTap != null) onTap.run();
                } else {
                    // Snap to nearest vertical edge
                    DisplayMetrics dm = getResources().getDisplayMetrics();
                    int cx = lp.x + getWidth() / 2;
                    lp.x = (cx < dm.widthPixels / 2) ? 0 : dm.widthPixels - getWidth();
                    if (wm != null) wm.updateViewLayout(this, lp);
                }
                return true;

            case MotionEvent.ACTION_CANCEL:
                longPressHandler.removeCallbacks(longPressRunnable);
                return true;
        }
        return false;
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    public void cleanup() {
        if (longPressRunnable != null) longPressHandler.removeCallbacks(longPressRunnable);
        if (animDrawable != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            animDrawable.stop();
            animDrawable = null;
        }
    }
}
