import QtQuick

// Compatibility name for shared loading indicators; Icon owns the animation.
QtObject {
  id: root
  property bool running: false
  readonly property string frame: "loader-circle"
}
