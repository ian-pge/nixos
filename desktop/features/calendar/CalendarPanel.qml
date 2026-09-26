pragma ComponentBehavior: Bound
import QtQuick
import "./Calendar.js" as Calendar
import "../../ui/Theme.js" as Theme
import "../../ui"

FocusScope {
  id: root

  required property var controller
  signal closeRequested()
  readonly property var cells: Calendar.monthCells(controller.year, controller.month)
  readonly property var weeks: Array.from({length: cells.length / 7},
    (_, index) => cells.slice(index * 7, index * 7 + 7))
  readonly property var weekHeights: weeks.map(week => week.reduce((height, day) => {
    const forecast = controller.weather.days[day.date];
    return Math.max(height, Calendar.temperatureRange(forecast) !== "" ? 60
      : Calendar.weatherIcon(forecast?.code) !== "" ? 44 : 24);
  }, 24))
  readonly property string todayKey: Calendar.dateKey(controller.today)
  readonly property string monthTitle: Calendar.monthTitle(controller.year, controller.month)
  readonly property bool detailsOpen: controller.detailsOpen
  readonly property bool locationSearchOpen: controller.weather.locationSearchOpen

  // Bar supplies the exact workspace ceiling; height never depends on wrapping.
  implicitHeight: updateLabel.y + updateLabel.height + 10

  onEnabledChanged: {
    if (enabled)
      Qt.callLater(root.restoreFocus);
  }
  Component.onCompleted: {
    if (enabled)
      Qt.callLater(root.restoreFocus);
  }

  function restoreFocus() {
    if (!enabled) return;
    if (locationSearchOpen) locationSelector.focusSearch();
    else forceActiveFocus();
  }
  onLocationSearchOpenChanged: Qt.callLater(restoreFocus)

  Keys.onPressed: event => {
    if (locationSearchOpen)
      return;
    if (event.key === Qt.Key_S)
      controller.weather.openLocationSearch();
    else if (event.key === Qt.Key_U || event.key === Qt.Key_PageUp)
      controller.moveMonth(-1);
    else if (event.key === Qt.Key_D || event.key === Qt.Key_PageDown)
      controller.moveMonth(1);
    else if (event.key === Qt.Key_Left || event.key === Qt.Key_H)
      controller.moveDay(-1);
    else if (event.key === Qt.Key_Right || event.key === Qt.Key_L)
      controller.moveDay(1);
    else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
      if (detailsOpen) dayDetails.scrollHours(1);
      else controller.moveDay(7);
    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
      if (detailsOpen) dayDetails.scrollHours(-1);
      else controller.moveDay(-7);
    } else if (event.key === Qt.Key_Home || event.key === Qt.Key_N)
      controller.goToday();
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
      controller.selectDate(controller.selectedDate, true);
    else if (event.key === Qt.Key_Escape) {
      if (detailsOpen) controller.detailsOpen = false;
      else root.closeRequested();
    }
    else
      return;
    event.accepted = true;
  }

  Text {
    x: 16; y: 12; width: 22; height: 24
    text: root.detailsOpen || root.locationSearchOpen ? "‹" : ""
    color: Theme.sideWeather
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 18
    verticalAlignment: Text.AlignVCenter
    MouseArea {
      objectName: "backToCalendar"
      anchors.fill: parent
      enabled: root.detailsOpen || root.locationSearchOpen
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (root.locationSearchOpen) root.controller.weather.closeLocationSearch();
        else root.controller.detailsOpen = false;
      }
    }
  }
  Text {
    x: 44; y: 12
    width: Math.max(0, parent.width - x - 16)
    height: 20
    text: root.locationSearchOpen ? "Localisation météo"
      : root.detailsOpen ? Calendar.detailTitle(root.controller.selectedDate) : root.monthTitle
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: Theme.foreground
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 14
    font.bold: true
    verticalAlignment: Text.AlignVCenter
  }
  Text {
    x: 44; y: 33; width: parent.width - 60; height: 12
    text: root.locationSearchOpen ? "↑/↓ choisir · Entrée valider · Échap retour"
      : root.detailsOpen ? "h/l jours · j/k défiler · n aujourd’hui · s ville · Échap"
      : "hjkl jours · u/d mois · n aujourd’hui · s ville · ↵"
    color: Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 9
  }
  Rectangle {
    x: 14; y: 46; width: parent.width - 28; height: 1
    color: Theme.surfaceRaised
  }
  Row {
    x: 16; y: 52
    visible: !root.detailsOpen && !root.locationSearchOpen
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
    visible: !root.detailsOpen && !root.locationSearchOpen
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
          delegate: SelectionSurface {
            id: cell
            required property var modelData
            readonly property bool isToday: modelData.date === root.todayKey
            readonly property bool isSelected: modelData.date === root.controller.selectedDate
            readonly property var forecast: root.controller.weather.days[modelData.date]
            readonly property string weatherIcon: Calendar.weatherIcon(forecast?.code)
            readonly property string temperatureText: Calendar.temperatureRange(forecast)
            objectName: modelData.date
            width: dayGrid.cellWidth
            height: week.height
            radius: 8
            selected: isSelected
            accent: Theme.calendarSelected
            idleColor: isToday
              ? (GlassState.enabled ? Qt.alpha(Theme.sideWeather, cell.tintOpacity) : Theme.surfaceRaised)
              : "transparent"
            border.width: !GlassState.enabled && (isSelected || isToday) ? 1 : 0
            border.color: isSelected ? Theme.calendarSelected : Theme.sideWeather
            Text {
              objectName: "dayNumber"
              anchors.horizontalCenter: parent.horizontalCenter
              y: 2; height: 18
              text: cell.modelData.day === 0 ? "" : cell.modelData.day
              color: cell.isSelected ? Theme.calendarSelected
                : cell.isToday ? Theme.sideWeather : Theme.foreground
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 13
              font.bold: cell.isSelected || cell.isToday
            }
            Text {
              objectName: "weatherIcon"
              anchors.horizontalCenter: parent.horizontalCenter
              y: 20; height: 22
              text: cell.modelData.day === 0 ? "" : cell.weatherIcon
              visible: text !== ""
              color: Calendar.weatherIconColor(cell.forecast?.code)
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 20
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
            }
            MouseArea {
              anchors.fill: parent
              enabled: cell.modelData.day > 0
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.controller.selectDate(cell.modelData.date, true);
                root.forceActiveFocus();
              }
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
  WeatherDayDetails {
    id: dayDetails
    objectName: "dayDetails"
    x: 16; y: 56; width: parent.width - 32; height: implicitHeight
    visible: root.detailsOpen && !root.locationSearchOpen
    forecast: root.controller.weather.days[root.controller.selectedDate] ?? null
    loading: root.controller.weather.loading
  }
  WeatherLocationSelector {
    id: locationSelector
    objectName: "locationSelector"
    x: 16; y: 56; width: parent.width - 32; height: implicitHeight
    weather: root.controller.weather
    visible: root.locationSearchOpen
    enabled: root.enabled && root.locationSearchOpen
    onClosed: root.controller.weather.closeLocationSearch()
  }
  Text {
    x: 16; y: updateLabel.y
    width: Math.max(0, updateLabel.x - x - 10)
    height: 16
    text: root.controller.weather.locationText + " · Open-Meteo"
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
    y: (root.locationSearchOpen ? locationSelector.y + locationSelector.height
      : root.detailsOpen ? dayDetails.y + dayDetails.height : dayGrid.y + dayGrid.height) + 10; height: 16
    text: root.controller.weather.updateText
    color: Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 10
  }
}
