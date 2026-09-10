pragma ComponentBehavior: Bound
import QtQuick
import "Calendar.js" as Calendar
import "Theme.js" as Theme

FocusScope {
  id: root

  required property var statusData
  readonly property var cells: Calendar.monthCells(statusData.calendarYear, statusData.calendarMonth)
  readonly property var weeks: Array.from({length: cells.length / 7},
    (_, index) => cells.slice(index * 7, index * 7 + 7))
  readonly property var weekHeights: weeks.map(week => week.reduce((height, day) => {
    const forecast = statusData.weather.days[day.date];
    return Math.max(height, Calendar.temperatureRange(forecast) !== "" ? 60
      : Calendar.weatherIcon(forecast?.code) !== "" ? 44 : 24);
  }, 24))
  readonly property string todayKey: Calendar.dateKey(statusData.calendarToday)
  readonly property string monthTitle: Calendar.monthTitle(statusData.calendarYear, statusData.calendarMonth)

  // Bar supplies the exact workspace ceiling; height never depends on wrapping.
  implicitHeight: updateLabel.y + updateLabel.height + 10

  onEnabledChanged: {
    if (enabled)
      Qt.callLater(() => { if (root.enabled) root.forceActiveFocus(); });
  }
  Component.onCompleted: {
    if (enabled)
      Qt.callLater(() => { if (root.enabled) root.forceActiveFocus(); });
  }

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_PageUp || event.key === Qt.Key_H)
      statusData.calendarMoveMonth(-1);
    else if (event.key === Qt.Key_Right || event.key === Qt.Key_PageDown || event.key === Qt.Key_L)
      statusData.calendarMoveMonth(1);
    else if (event.key === Qt.Key_Home || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
      statusData.calendarGoToday();
    else if (event.key === Qt.Key_Escape)
      statusData.hideCalendar();
    else
      return;
    event.accepted = true;
  }

  Text {
    x: 16; y: 12; width: 22; height: 24
    text: ""
    color: Theme.sideWeather
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 18
    verticalAlignment: Text.AlignVCenter
  }
  Text {
    x: 44; y: 12
    width: Math.max(0, parent.width - x - 16)
    height: 24
    text: root.monthTitle
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: Theme.foreground
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 14
    font.bold: true
    verticalAlignment: Text.AlignVCenter
  }
  Rectangle {
    x: 14; y: 46; width: parent.width - 28; height: 1
    color: Theme.surfaceRaised
  }
  Row {
    x: 16; y: 52
    spacing: 4
    Repeater {
      model: ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
      delegate: Text {
        required property string modelData
        width: dayGrid.cellWidth; height: 18
        text: modelData
        color: Theme.secondary
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 11
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
  Column {
    id: dayGrid
    objectName: "dayGrid"
    x: 16; y: 76
    width: parent.width - 32
    spacing: 4
    // Size from data, not a layout pass: covered/off-monitor panels must update too.
    height: root.weekHeights.reduce((sum, height) => sum + height, 0)
      + Math.max(0, root.weeks.length - 1) * spacing
    readonly property real cellWidth: Math.max(0, (width - 6 * spacing) / 7)
    Repeater {
      model: root.weeks
      delegate: Row {
        id: week
        required property int index
        required property var modelData
        objectName: "week" + index
        width: dayGrid.width
        spacing: dayGrid.spacing
        // All seven cells share the space required by this week's visible data.
        height: root.weekHeights[index]
        Repeater {
          model: week.modelData
          delegate: Rectangle {
            id: cell
            required property var modelData
            readonly property bool isToday: modelData.date === root.todayKey
            readonly property var forecast: root.statusData.weather.days[modelData.date]
            readonly property string weatherIcon: Calendar.weatherIcon(forecast?.code)
            readonly property string temperatureText: Calendar.temperatureRange(forecast)
            objectName: modelData.date
            width: dayGrid.cellWidth
            height: week.height
            radius: 8
            color: isToday ? Theme.surfaceRaised : "transparent"
            border.width: isToday ? 1 : 0
            border.color: Theme.sideWeather
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              y: 2; height: 18
              text: cell.modelData.day === 0 ? "" : cell.modelData.day
              color: cell.isToday ? Theme.sideWeather : Theme.foreground
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 13
              font.bold: cell.isToday
            }
            Text {
              objectName: "weatherIcon"
              anchors.horizontalCenter: parent.horizontalCenter
              y: 20; height: 22
              text: cell.modelData.day === 0 ? "" : cell.weatherIcon
              visible: text !== ""
              color: Theme.sideWeather
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 20
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
            }
            Text {
              objectName: "temperature"
              x: 2; y: 44; width: parent.width - 4; height: 14
              text: cell.modelData.day === 0 ? "" : cell.temperatureText
              visible: text !== ""
              color: Theme.sideWeather
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 10
              minimumPixelSize: 8
              fontSizeMode: Text.HorizontalFit
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
            }
          }
        }
      }
    }
  }
  Text {
    x: 16; y: updateLabel.y
    width: Math.max(0, updateLabel.x - x - 10)
    height: 16
    text: root.statusData.weather.locationText + " · Open-Meteo"
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 10
  }
  Text {
    id: updateLabel
    objectName: "updateLabel"
    anchors.right: parent.right
    anchors.rightMargin: 16
    y: dayGrid.y + dayGrid.height + 10; height: 16
    text: root.statusData.weather.updateText
    color: Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 10
  }
}
