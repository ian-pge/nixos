#include "glassshape.hpp"
#include "liquid-glass-client.h"
#include <QGuiApplication>
#include <QPointer>
#include <QQuickWindow>
#include <QWaylandClientExtension>
#include <algorithm>
#include <array>
#include <cmath>
#include <qpa/qplatformwindow_p.h>
#include <vector>

namespace {
class Extension : public QWaylandClientExtension {
  public:
    ian_liquid_glass_v1* manager = nullptr;
    uint64_t epoch = 0;
    Extension() : QWaylandClientExtension(1) {
        connect(this, &QWaylandClientExtension::activeChanged, this, [this] {
            ++epoch;
            if (!isActive() && manager) {
                ian_liquid_glass_v1_destroy(manager);
                manager = nullptr;
            }
            for (auto* window : QGuiApplication::allWindows()) {
                if (auto* quick = qobject_cast<QQuickWindow*>(window))
                    quick->update();
                else
                    window->requestUpdate();
            }
        });
    }
    ~Extension() override {
        if (manager)
            ian_liquid_glass_v1_destroy(manager);
    }
    const wl_interface* extensionInterface() const override { return &ian_liquid_glass_v1_interface; }
    void bind(wl_registry* registry, int name, int) override {
        manager =
            static_cast<ian_liquid_glass_v1*>(wl_registry_bind(registry, name, &ian_liquid_glass_v1_interface, 1));
        setVersion(1);
    }
};
Extension* extension() {
    static QPointer<Extension> instance;
    static const bool matchingQt = QString::fromLatin1(qVersion()) == QString::fromLatin1(QT_VERSION_STR);
    static const bool disabled = qEnvironmentVariableIntValue("LIQUID_GLASS_DISABLE_GEOMETRY") == 1;
    if (!matchingQt || disabled)
        return nullptr; // The native wl_surface accessor is Qt-version-specific.
    if (!instance && QGuiApplication::platformName().startsWith("wayland")) {
        instance = new Extension;
        instance->setParent(qGuiApp);
    }
    return instance;
}

class Reporter : public QObject {
    QQuickWindow* m_window;
    Extension* m_extension;
    QPointer<QNativeInterface::Private::QWaylandWindow> m_native;
    wl_surface* m_lastSurface = nullptr;
    ian_liquid_glass_v1* m_lastManager = nullptr;
    std::vector<int32_t> m_last;
    QSize m_size;
    bool m_valid = false;
    uint64_t m_epoch = 0;

  public:
    Reporter(QQuickWindow* window, Extension* ext) : QObject(window), m_window(window), m_extension(ext) {
        setObjectName("liquid-glass-geometry-reporter");
        connect(window, &QQuickWindow::beforeSynchronizing, this, [this] { sync(); }, Qt::DirectConnection);
    }
    void sync() {
        // Qt blocks the GUI thread during this direct signal. All item state
        // belongs to the frame about to render, and requests use the very same
        // Wayland connection before its wl_surface.commit (no per-frame IPC process).
        if (!m_extension->isActive() || !m_extension->manager)
            return;
        auto* native = m_window->nativeInterface<QNativeInterface::Private::QWaylandWindow>();
        if (!native || !native->surface())
            return;
        if (m_native != native) {
            m_native = native;
            connect(
                native, &QNativeInterface::Private::QWaylandWindow::surfaceDestroyed, this,
                [this] { m_lastSurface = nullptr; }, Qt::DirectConnection);
            connect(
                native, &QNativeInterface::Private::QWaylandWindow::surfaceCreated, this,
                [this] { m_lastSurface = nullptr; }, Qt::DirectConnection);
        }
        std::vector<int32_t> values;
        bool valid = true;
        std::vector<GlassShape*> shapes;
        std::vector<QQuickItem*> items{m_window->contentItem()};
        while (!items.empty()) {
            auto* item = items.back();
            items.pop_back();
            if (auto* shape = qobject_cast<GlassShape*>(item))
                shapes.push_back(shape);
            const auto children = item->childItems();
            for (auto it = children.crbegin(); it != children.crend(); ++it)
                items.push_back(*it);
        }
        for (auto* shape : shapes) {
            if (!shape->isVisible() || !shape->isEnabled() || shape->width() <= 0 || shape->height() <= 0)
                continue;
            qreal opacity = 1;
            for (auto* item = static_cast<QQuickItem*>(shape); item; item = item->parentItem())
                opacity *= item->opacity();
            if (opacity < 0.001)
                continue;
            const auto p = shape->mapToScene(QPointF{0, 0});
            const auto x = shape->mapToScene(QPointF{shape->width(), 0});
            const auto y = shape->mapToScene(QPointF{0, shape->height()});
            const qreal width = x.x() - p.x(), height = y.y() - p.y();
            // Vanishing animation frames can quantize a positive size to zero.
            // They have no visible area and must not become a protocol error.
            if (width > 0 && height > 0 && (width < 1.0 / 256.0 || height < 1.0 / 256.0))
                continue;
            // Translation and uniform scale are exact. Unsupported transforms
            // request the existing raster fallback, never a guessed rectangle.
            if (std::abs(x.y() - p.y()) > 0.001 || std::abs(y.x() - p.x()) > 0.001 || width <= 0 || height <= 0 ||
                std::abs(width / shape->width() - height / shape->height()) > 0.001 || values.size() >= 64 * 6) {
                valid = false;
                break;
            }
            const qreal radius = std::clamp(shape->m_radius * width / shape->width(), 0.0, std::min(width, height) / 2);
            for (qreal value : {p.x(), p.y(), width, height, radius, opacity}) {
                if (!std::isfinite(value) || std::abs(value) > 32768) {
                    valid = false;
                    break;
                }
                values.push_back(wl_fixed_from_double(value));
            }
            if (!valid)
                break;
        }
        if (!valid)
            values.clear();
        auto* surface = native->surface();
        const auto size = m_window->size();
        if (m_epoch == m_extension->epoch && surface == m_lastSurface && m_extension->manager == m_lastManager &&
            values == m_last && size == m_size && valid == m_valid)
            return;
        wl_array array{values.size() * sizeof(int32_t), values.size() * sizeof(int32_t), values.data()};
        ian_liquid_glass_v1_set_geometry(m_extension->manager, surface, size.width(), size.height(), valid, &array);
        m_last = std::move(values);
        m_lastSurface = surface;
        m_lastManager = m_extension->manager;
        m_size = size;
        m_valid = valid;
        m_epoch = m_extension->epoch;
    }
};
} // namespace

GlassShape::GlassShape(QQuickItem* parent) : QQuickItem(parent) {
    connect(this, &QQuickItem::windowChanged, this, [](QQuickWindow* window) {
        auto* ext = extension();
        if (!window || !ext ||
            window->findChild<QObject*>("liquid-glass-geometry-reporter", Qt::FindDirectChildrenOnly))
            return;
        new Reporter(window, ext);
        window->update();
    });
}
