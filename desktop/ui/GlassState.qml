pragma Singleton
import QtQuick

// Keep opaque backgrounds unless the matching compositor plugin is available.
QtObject {
  property bool enabled: false
}
