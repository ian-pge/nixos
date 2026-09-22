#pragma once
#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

class GlassShape : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal radius MEMBER m_radius NOTIFY radiusChanged)
  public:
    explicit GlassShape(QQuickItem* parent = nullptr);
    qreal m_radius = 18;
  signals:
    void radiusChanged();
};
