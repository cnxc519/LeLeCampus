#include "imageutil.h"
#include <QImage>
#include <QImageReader>
#include <QImageWriter>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>
#include <QRandomGenerator>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#include <QCoreApplication>

// Android 相册选择器返回 content:// URI，QFile/QImageReader 无法直接读取；
// 通过 ContentResolver.openInputStream 把图片字节读进内存
static QByteArray readContentUri(const QUrl &url)
{
    QJniObject context = QNativeInterface::QAndroidApplication::context();
    if (!context.isValid()) return {};
    QJniObject juri = QJniObject::fromString(url.toString());
    QJniObject resolver = context.callObjectMethod("getContentResolver",
        "()Landroid/content/ContentResolver;");
    if (!resolver.isValid()) return {};
    QJniObject is = resolver.callObjectMethod("openInputStream",
        "(Landroid/net/Uri;)Ljava/io/InputStream;", juri.object());
    if (!is.isValid()) return {};

    QJniEnvironment env;
    jclass baosCls = env.findClass("java/io/ByteArrayOutputStream");
    if (!baosCls) { env.checkAndClearExceptions(); return {}; }
    jmethodID ctor = env->GetMethodID(baosCls, "<init>", "()V");
    QJniObject baos(env->NewObject(baosCls, ctor));
    QJniObject buf(env->NewByteArray(16 * 1024));

    jint total = 0;
    const jint cap = 20 * 1024 * 1024; // 防异常大文件撑爆内存
    while (total < cap) {
        const jint n = is.callMethod<jint>("read", "([B)I", buf.object());
        if (n <= 0) break;
        baos.callMethod<void>("write", "([BII)V", buf.object(), 0, n);
        total += n;
    }
    env.checkAndClearExceptions();

    QJniObject bytes = baos.callObjectMethod("toByteArray", "()[B");
    if (!bytes.isValid()) { env.checkAndClearExceptions(); return {}; }
    const jint len = bytes.callMethod<jint>("length");
    QByteArray out(len, Qt::Uninitialized);
    env->GetByteArrayRegion(static_cast<jbyteArray>(bytes.object()), 0, len,
                            reinterpret_cast<jbyte *>(out.data()));
    env.checkAndClearExceptions();
    return out;
}
#endif

ImageUtil::ImageUtil(QObject *parent) : QObject(parent) {}

QString ImageUtil::compress(const QUrl &src, int maxDim, int maxKb)
{
    QImage img;
#ifdef Q_OS_ANDROID
    // content://（相册选择器）走 ContentResolver 读字节流
    if (src.scheme() == QLatin1String("content")) {
        const QByteArray bytes = readContentUri(src);
        if (bytes.isEmpty()) return QString();
        img = QImage::fromData(bytes); // 自动识别 JPEG/PNG
    } else
#endif
    {
        const QString srcPath = src.toLocalFile();
        if (srcPath.isEmpty() || !QFile::exists(srcPath))
            return QString();

        QImageReader reader(srcPath);
        if (!reader.canRead())
            return QString();

        img = reader.read();
    }
    if (img.isNull())
        return QString();

    // 等比缩放到最长边 <= maxDim
    if (img.width() > maxDim || img.height() > maxDim) {
        if (img.width() >= img.height())
            img = img.scaledToWidth(maxDim, Qt::SmoothTransformation);
        else
            img = img.scaledToHeight(maxDim, Qt::SmoothTransformation);
    }

    // 从质量 80 起逐步降低，直到大小 <= maxKb（最低 25，保证可辨认）
    QString dir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    QString out = dir + QLatin1String("/lele_img_")
            + QString::number(QRandomGenerator::global()->bounded(100000, 999999)) + QLatin1String(".jpg");

    int quality = 80;
    do {
        QImageWriter writer(out, "jpg");
        writer.setQuality(quality);
        if (!writer.write(img))
            return QString();
        quality -= 15;
    } while (quality >= 25 && QFileInfo(out).size() > maxKb * 1024);

    return QFileInfo(out).size() > 0 ? QUrl::fromLocalFile(out).toString() : QString();
}
