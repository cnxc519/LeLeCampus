package com.lele.daipao;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.net.Uri;

/**
 * 相册图片读取/解码助手（纯 Java，异常自兜底）。
 *
 * 之所以放 Java 里做：此前 C++ 经 JNI 逐段读 ContentResolver.openInputStream 字节流，
 * 在 x86_64 模拟器上 ContentResolver.openInputStream 内部直接 SIGSEGV（java.lang.String.getChars
 * 里崩掉整个进程）；真机 HEIC/HEIF 照片 Qt 的 QImage 也解不了。
 * 这里一次调用完成「读流→按尺寸采样→缩放→压成 JPEG 字节」，任何一步失败返回 null，
 * C++ 侧只拿结果，不再碰 ContentResolver 的流。
 */
public class ImageHelper {

    /**
     * 读取 content:// 或 file:// 图片并输出为 JPEG 字节。
     * @param maxDim 输出最长边上限（像素）
     * @param quality JPEG 质量 1-100
     * @return JPEG 字节；失败返回 null
     */
    public static byte[] readScaledJpeg(Context ctx, Uri uri, int maxDim, int quality) {
        try {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            decode(ctx, uri, bounds);
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null;

            // inSampleSize 采样：先粗降到目标的一半以内，避免大图整张进内存
            int sample = 1;
            while (bounds.outWidth / (sample * 2) >= maxDim && bounds.outHeight / (sample * 2) >= maxDim) {
                sample *= 2;
            }
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inSampleSize = sample;
            Bitmap bmp = decode(ctx, uri, opts);
            if (bmp == null) return null;

            // 采样后仍超过 maxDim 再精确缩放一次
            int w = bmp.getWidth(), h = bmp.getHeight();
            if (w > maxDim || h > maxDim) {
                float scale = w >= h ? (float) maxDim / w : (float) maxDim / h;
                Matrix m = new Matrix();
                m.postScale(scale, scale);
                Bitmap scaled = Bitmap.createBitmap(bmp, 0, 0, w, h, m, true);
                if (scaled != bmp) bmp.recycle();
                bmp = scaled;
            }

            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            bmp.compress(Bitmap.CompressFormat.JPEG, quality, out);
            bmp.recycle();
            return out.toByteArray();
        } catch (Throwable t) {
            return null;
        }
    }

    private static Bitmap decode(Context ctx, Uri uri, BitmapFactory.Options opts) {
        java.io.InputStream is = null;
        try {
            is = ctx.getContentResolver().openInputStream(uri);
            if (is == null) return null;
            return BitmapFactory.decodeStream(is, null, opts);
        } catch (Throwable t) {
            return null;
        } finally {
            if (is != null) { try { is.close(); } catch (Throwable ignored) {} }
        }
    }
}
