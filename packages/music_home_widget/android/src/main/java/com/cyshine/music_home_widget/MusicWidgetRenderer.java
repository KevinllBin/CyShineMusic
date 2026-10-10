package com.cyshine.music_home_widget;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.CornerPathEffect;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import android.text.TextUtils;

import java.util.Random;

/** One bounded bitmap gives RemoteViews the card's soft, layered material. */
final class MusicWidgetRenderer {
    static Bitmap render(int width, int height, String title, String artist,
            boolean playing, boolean loading, Bitmap cover) {
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        float unit = Math.min(width, height);
        float radius = unit * .155f;
        RectF bounds = new RectF(0, 0, width, height);
        Path outline = new Path();
        outline.addRoundRect(bounds, radius, radius, Path.Direction.CW);
        canvas.save();
        canvas.clipPath(outline);

        int base = backgroundColor(cover);
        paint.setShader(new LinearGradient(0, 0, width, height,
                new int[]{alpha(blend(base, Color.WHITE, .10f), 225), alpha(base, 230),
                        alpha(blend(base, Color.BLACK, .04f), 234)},
                null, Shader.TileMode.CLAMP));
        canvas.drawRect(bounds, paint);
        paint.setShader(null);

        if (cover != null) {
            float coverSize = Math.max(width * .82f, height * .74f);
            RectF artwork = new RectF(0, height * .30f, coverSize, height * .30f + coverSize);
            float coverRadius = unit * .025f;
            Path coverOutline = new Path();
            coverOutline.addRoundRect(artwork, coverRadius, coverRadius, Path.Direction.CW);
            canvas.save();
            canvas.rotate(8.5f, artwork.left, artwork.top);
            paint.setColor(0xFFF0EBDF);
            paint.setShadowLayer(unit * .014f, 0, unit * .008f, 0x26000000);
            canvas.drawRoundRect(artwork, coverRadius, coverRadius, paint);
            paint.clearShadowLayer();
            canvas.clipPath(coverOutline);
            paint.setColor(Color.WHITE);
            paint.setAlpha(244);
            canvas.drawBitmap(cover, new Rect(0, 0, cover.getWidth(), cover.getHeight()), artwork, paint);
            canvas.restore();
            paint.setColor(Color.WHITE);
        } else {
            drawNote(canvas, width * .30f, height * .55f, unit * .22f, 75, paint);
        }

        paint.setColor(Color.WHITE);
        paint.setShader(new RadialGradient(width * .10f, height * .08f, unit * .90f,
                0x20FFFFFF, 0x00FFFFFF, Shader.TileMode.CLAMP));
        canvas.drawRect(bounds, paint);
        paint.setShader(new LinearGradient(0, 0, 0, height * .38f,
                0x1C07151D, 0x0007151D, Shader.TileMode.CLAMP));
        canvas.drawRect(bounds, paint);
        paint.setShader(null);

        Random random = new Random(20261008L);
        for (int i = 0; i < 1600; i++) {
            paint.setColor(i % 2 == 0 ? 0x08FFFFFF : 0x05000000);
            float x = random.nextFloat() * width;
            float y = random.nextFloat() * height;
            canvas.drawCircle(x, y, Math.max(.35f, unit / 800f), paint);
        }

        TextPaint text = new TextPaint(Paint.ANTI_ALIAS_FLAG);
        float[] accentHsv = new float[3];
        Color.colorToHSV(base, accentHsv);
        accentHsv[1] = Math.min(.22f, accentHsv[1] * .6f);
        accentHsv[2] = 1f;
        int accent = Color.HSVToColor(accentHsv);
        text.setColor(blend(accent, Color.WHITE, .55f));
        text.setTextSize(Math.min(width * .080f, height * .085f));
        text.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        text.setShadowLayer(unit * .008f, 0, unit * .003f, 0x60000000);
        String heading = title.isEmpty() ? "栖弦音乐" : title;
        StaticLayout label = StaticLayout.Builder.obtain(heading, 0, heading.length(), text,
                        Math.max(1, Math.round(width * .64f)))
                .setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(false)
                .setLineSpacing(0, 1.12f).setMaxLines(2)
                .setEllipsize(TextUtils.TruncateAt.END).build();
        canvas.save();
        canvas.translate(width * .10f, height * .092f);
        label.draw(canvas);
        canvas.restore();
        String byline = title.isEmpty() ? "点击开始播放" : artist;
        if (!byline.isEmpty()) {
            text.setColor(alpha(blend(accent, Color.WHITE, .25f), 238));
            text.setTextSize(unit * .052f);
            text.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            StaticLayout author = StaticLayout.Builder.obtain(byline, 0, byline.length(), text,
                            Math.max(1, Math.round(width * .64f)))
                    .setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(false)
                    .setMaxLines(1).setEllipsize(TextUtils.TruncateAt.END).build();
            canvas.save();
            canvas.translate(width * .10f, height * .092f + label.getHeight() + unit * .025f);
            author.draw(canvas);
            canvas.restore();
        }
        drawNote(canvas, width * .80f, height * .104f, unit * .115f, 255, paint);

        float buttonRadius = unit * .090f;
        float buttonY = height * .83f;
        // Frozen backdrop sampling softens the cover under each glass button.
        Bitmap backdrop = blurBackdrop(bitmap);
        for (int i = 0; i < 3; i++) {
            float x = width * (.20f + i * .30f);
            drawButton(canvas, backdrop, width, height, x, buttonY, buttonRadius, base, paint);
            paint.setColor(Color.WHITE);
            paint.setStyle(Paint.Style.FILL);
            paint.setPathEffect(new CornerPathEffect(unit * .006f));
            float icon = buttonRadius * .43f;
            if (i == 1 && loading) {
                for (int dot = -1; dot <= 1; dot++) {
                    canvas.drawCircle(x + dot * icon * .85f, buttonY, icon * .19f, paint);
                }
            } else if (i == 1 && playing) {
                float bar = icon * .43f;
                canvas.drawRoundRect(new RectF(x - icon * .82f, buttonY - icon,
                        x - icon * .82f + bar, buttonY + icon), bar * .18f, bar * .18f, paint);
                canvas.drawRoundRect(new RectF(x + icon * .39f, buttonY - icon,
                        x + icon * .39f + bar, buttonY + icon), bar * .18f, bar * .18f, paint);
            } else if (i == 1) {
                triangle(canvas, x + icon * .13f, buttonY, icon * 1.05f, true, paint);
            } else {
                boolean right = i == 2;
                triangle(canvas, x - icon * .54f, buttonY, icon * .78f, right, paint);
                triangle(canvas, x + icon * .54f, buttonY, icon * .78f, right, paint);
            }
            paint.setPathEffect(null);
        }
        backdrop.recycle();

        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(Math.max(1f, unit * .004f));
        paint.setShader(new LinearGradient(0, 0, width, height,
                0xAAFFFFFF, 0x20FFFFFF, Shader.TileMode.CLAMP));
        float inset = paint.getStrokeWidth() / 2;
        canvas.drawRoundRect(new RectF(inset, inset, width - inset, height - inset), radius, radius, paint);
        paint.setShader(null);
        canvas.restore();
        return bitmap;
    }

    private static void drawButton(Canvas canvas, Bitmap backdrop, int width, int height,
            float x, float y, float radius, int base, Paint paint) {
        paint.setColor(0x16000000);
        paint.setShadowLayer(radius * .16f, 0, radius * .09f, 0x30000000);
        canvas.drawCircle(x, y, radius, paint);
        paint.clearShadowLayer();
        Path circle = new Path();
        circle.addCircle(x, y, radius, Path.Direction.CW);
        canvas.save();
        canvas.clipPath(circle);
        paint.setColor(Color.WHITE);
        // A small magnification refracts the blurred artwork through the lens.
        float zoom = 1.08f;
        canvas.drawBitmap(backdrop, null, new RectF(x * (1 - zoom), y * (1 - zoom),
                width * zoom + x * (1 - zoom), height * zoom + y * (1 - zoom)), paint);
        int tint = blend(base, Color.WHITE, .35f);
        paint.setShader(new LinearGradient(x, y - radius, x, y + radius,
                alpha(blend(tint, Color.WHITE, .20f), 110), alpha(tint, 65), Shader.TileMode.CLAMP));
        canvas.drawCircle(x, y, radius, paint);
        paint.setShader(new RadialGradient(x - radius * .35f, y - radius * .7f, radius * 1.8f,
                0x50FFFFFF, 0x00FFFFFF, Shader.TileMode.CLAMP));
        canvas.drawCircle(x, y, radius, paint);
        paint.setShader(null);
        canvas.restore();
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(Math.max(1f, radius * .032f));
        paint.setShader(new LinearGradient(x, y - radius, x, y + radius,
                0xBEFFFFFF, 0x28FFFFFF, Shader.TileMode.CLAMP));
        canvas.drawCircle(x, y, radius - paint.getStrokeWidth() / 2, paint);
        paint.setShader(null);
        paint.setColor(0x88FFFFFF);
        paint.setStrokeWidth(Math.max(.7f, radius * .016f));
        float inner = radius - paint.getStrokeWidth() * 2;
        canvas.drawArc(new RectF(x - inner, y - inner, x + inner, y + inner), 225, 85, false, paint);
        paint.setStyle(Paint.Style.FILL);
    }

    private static Bitmap blurBackdrop(Bitmap bitmap) {
        float scale = Math.min(1f, 64f / Math.max(bitmap.getWidth(), bitmap.getHeight()));
        int width = Math.max(1, Math.round(bitmap.getWidth() * scale));
        int height = Math.max(1, Math.round(bitmap.getHeight() * scale));
        Bitmap blurred = Bitmap.createScaledBitmap(bitmap, width, height, true);
        // createScaledBitmap may return its input for very small widget sizes.
        if (blurred == bitmap) blurred = bitmap.copy(Bitmap.Config.ARGB_8888, true);
        int[] pixels = new int[width * height];
        int[] scratch = new int[pixels.length];
        blurred.getPixels(pixels, 0, width, 0, 0, width, height);
        int[] weights = {1, 4, 6, 4, 1};
        for (int pass = 0; pass < 2; pass++) {
            for (int direction = 0; direction < 2; direction++) {
                for (int y = 0; y < height; y++) {
                    for (int x = 0; x < width; x++) {
                        int a = 0, r = 0, g = 0, b = 0;
                        for (int offset = -2; offset <= 2; offset++) {
                            int sx = direction == 0 ? Math.max(0, Math.min(width - 1, x + offset)) : x;
                            int sy = direction == 1 ? Math.max(0, Math.min(height - 1, y + offset)) : y;
                            int color = pixels[sy * width + sx];
                            int weight = weights[offset + 2];
                            a += Color.alpha(color) * weight;
                            r += Color.red(color) * weight;
                            g += Color.green(color) * weight;
                            b += Color.blue(color) * weight;
                        }
                        scratch[y * width + x] = Color.argb(a / 16, r / 16, g / 16, b / 16);
                    }
                }
                int[] swap = pixels;
                pixels = scratch;
                scratch = swap;
            }
        }
        blurred.setPixels(pixels, 0, width, 0, 0, width, height);
        return blurred;
    }

    private static void triangle(Canvas canvas, float x, float y, float size, boolean right, Paint paint) {
        float direction = right ? 1 : -1;
        Path path = new Path();
        path.moveTo(x - direction * size * .65f, y - size);
        path.lineTo(x + direction * size, y);
        path.lineTo(x - direction * size * .65f, y + size);
        path.close();
        canvas.drawPath(path, paint);
    }

    private static void drawNote(Canvas canvas, float x, float y, float size, int opacity, Paint paint) {
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(size / 100f, size / 100f);
        paint.setColor(alpha(Color.WHITE, opacity));
        paint.setStyle(Paint.Style.FILL);
        Path stems = new Path();
        stems.moveTo(27, 13); stems.lineTo(95, 0); stems.lineTo(95, 76);
        stems.lineTo(83, 76); stems.lineTo(83, 30); stems.lineTo(39, 39);
        stems.lineTo(39, 88); stems.lineTo(27, 88); stems.close();
        canvas.drawPath(stems, paint);
        canvas.drawOval(new RectF(5, 73, 39, 97), paint);
        canvas.drawOval(new RectF(61, 62, 95, 86), paint);
        canvas.restore();
    }

    private static int backgroundColor(Bitmap cover) {
        if (cover == null) return 0xFF668F9C;
        float[][] buckets = new float[12][4];
        float[] hsv = new float[3];
        // Prefer the album's surrounding/background colors. Sampling the
        // entire portrait by saturation previously let skin dominate the sky.
        for (int y = 0; y < 24; y++) {
            for (int x = 0; x < 24; x++) {
                boolean upperBackground = y < 11;
                boolean sideBackground = x < 4 || x >= 20;
                if (!upperBackground && !sideBackground) continue;
                int color = cover.getPixel(x * cover.getWidth() / 24, y * cover.getHeight() / 24);
                if (Color.alpha(color) < 128) continue;
                Color.colorToHSV(color, hsv);
                if (hsv[2] < .20f || hsv[2] > .96f || hsv[1] < .10f) continue;
                int bucket = Math.min(11, (int) (hsv[0] / 30));
                float weight = Math.min(.55f, hsv[1]) * (upperBackground ? 2f : 1f);
                buckets[bucket][0] += Color.red(color) * weight;
                buckets[bucket][1] += Color.green(color) * weight;
                buckets[bucket][2] += Color.blue(color) * weight;
                buckets[bucket][3] += weight;
            }
        }
        float[] chosen = buckets[0];
        for (float[] bucket : buckets) if (bucket[3] > chosen[3]) chosen = bucket;
        if (chosen[3] == 0) return 0xFF668F9C;
        Color.colorToHSV(Color.rgb((int) (chosen[0] / chosen[3]),
                (int) (chosen[1] / chosen[3]), (int) (chosen[2] / chosen[3])), hsv);
        hsv[1] = Math.max(.14f, Math.min(.40f, hsv[1] * .85f));
        hsv[2] = Math.max(.68f, Math.min(.82f, hsv[2] * .90f + .14f));
        return Color.HSVToColor(hsv);
    }

    private static int blend(int color, int other, float amount) {
        return Color.rgb(Math.round(Color.red(color) * (1 - amount) + Color.red(other) * amount),
                Math.round(Color.green(color) * (1 - amount) + Color.green(other) * amount),
                Math.round(Color.blue(color) * (1 - amount) + Color.blue(other) * amount));
    }

    private static int alpha(int color, int alpha) { return (color & 0x00FFFFFF) | (alpha << 24); }
}
