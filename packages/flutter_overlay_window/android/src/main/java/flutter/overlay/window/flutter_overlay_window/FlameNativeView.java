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
import android.view.WindowManager;
import android.widget.ImageView;

import java.io.IOException;

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
    private Runnable onLongPressStart;
    private Runnable onLongPressEnd;

    private float touchDownX, touchDownY;
    private int   paramDownX, paramDownY;
    private boolean dragging = false;
    private boolean longPressActive = false; // true while a press is in progress (recording)
    private static final int   SLOP             = 16;  // px — less than this = tap vs drag
    private static final long  HOLD_DELAY_MS    = 400; // must be still this long to start recording
    private final Handler      holdHandler      = new Handler(Looper.getMainLooper());
    private Runnable           holdRunnable     = null;

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
     *
     * Push-to-talk model: recording starts on press-down (pressStartCallback)
     * and stops on finger-lift (pressEndCallback). Dart decides whether the
     * resulting audio is a real voice message or a quick tap (by checking file
     * size), and acts accordingly (expand vs transcribe+send).
     *
     * @param tapCallback      unused — kept for API compat; Dart handles tap via file-size check
     * @param pressStartCallback fires immediately on ACTION_DOWN
     * @param pressEndCallback   fires on ACTION_UP (non-drag) and ACTION_CANCEL
     */
    public void attach(WindowManager windowManager,
                       WindowManager.LayoutParams layoutParams,
                       Runnable tapCallback,
                       Runnable pressStartCallback,
                       Runnable pressEndCallback) {
        this.wm               = windowManager;
        this.lp               = layoutParams;
        this.onTap            = tapCallback;     // kept for compat, not currently fired
        this.onLongPressStart = pressStartCallback;
        this.onLongPressEnd   = pressEndCallback;
    }

    public void setHasPending(boolean pending) {
        // Badge logic can be added later (e.g. overlay a dot drawable)
    }

    // ── Touch ─────────────────────────────────────────────────────────────────

    @Override
    public boolean dispatchTouchEvent(MotionEvent e) {
        switch (e.getAction()) {

            case MotionEvent.ACTION_DOWN:
                touchDownX    = e.getRawX();
                touchDownY    = e.getRawY();
                paramDownX    = lp.x;
                paramDownY    = lp.y;
                dragging      = false;
                longPressActive = false;
                // Schedule recording start — only fires if finger stays still for HOLD_DELAY_MS.
                // Any drag detected in ACTION_MOVE will cancel this runnable first.
                holdHandler.removeCallbacks(holdRunnable != null ? holdRunnable : () -> {});
                holdRunnable = () -> {
                    if (!dragging) {
                        longPressActive = true;
                        if (onLongPressStart != null) onLongPressStart.run();
                    }
                };
                holdHandler.postDelayed(holdRunnable, HOLD_DELAY_MS);
                return true;

            case MotionEvent.ACTION_MOVE:
                float dx = e.getRawX() - touchDownX;
                float dy = e.getRawY() - touchDownY;
                if (!dragging && Math.abs(dx) < SLOP && Math.abs(dy) < SLOP) {
                    return true;
                }
                // User started dragging — cancel pending hold timer and any active recording
                holdHandler.removeCallbacks(holdRunnable != null ? holdRunnable : () -> {});
                if (!dragging && longPressActive) {
                    longPressActive = false;
                    if (onLongPressEnd != null) onLongPressEnd.run(); // cancel in Dart
                }
                dragging = true;
                lp.x = paramDownX + (int) dx;
                lp.y = paramDownY + (int) dy;
                if (wm != null) wm.updateViewLayout(this, lp);
                return true;

            case MotionEvent.ACTION_UP:
                holdHandler.removeCallbacks(holdRunnable != null ? holdRunnable : () -> {});
                if (dragging) {
                    // End of drag — snap to nearest vertical edge
                    DisplayMetrics dm = getResources().getDisplayMetrics();
                    int cx = lp.x + getWidth() / 2;
                    lp.x = (cx < dm.widthPixels / 2) ? 0 : dm.widthPixels - getWidth();
                    if (wm != null) wm.updateViewLayout(this, lp);
                } else if (longPressActive) {
                    // Finger lifted — stop recording (Dart checks file size to
                    // distinguish a true tap from a voice message)
                    longPressActive = false;
                    if (onLongPressEnd != null) onLongPressEnd.run();
                }
                return true;

            case MotionEvent.ACTION_CANCEL:
                holdHandler.removeCallbacks(holdRunnable != null ? holdRunnable : () -> {});
                if (longPressActive) {
                    longPressActive = false;
                    if (onLongPressEnd != null) onLongPressEnd.run();
                }
                return true;
        }
        return false;
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    public void cleanup() {
        if (animDrawable != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            animDrawable.stop();
            animDrawable = null;
        }
    }
}
