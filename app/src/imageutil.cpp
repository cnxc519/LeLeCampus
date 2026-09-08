#include "imageutil.h"
#include <QImage>
#include <QImageReader>
#include <QImageWriter>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>
#include <QRandomGenerator>

ImageUtil::ImageUtil(QObject *parent) : QObject(parent) {}

QString ImageUtil::compress(const QUrl &src, int maxDim, int maxKb)
{
    const QString srcPath = src.toLocalFile();
    if (srcPath.isEmpty() || !QFile::exists(srcPath))
        return QString();

    QImageReader reader(srcPath);
    if (!reader.canRead())
        return QString();

    QImage img = reader.read();
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
    QString out = dir + QLatin1String("/lele_avatar_")
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
