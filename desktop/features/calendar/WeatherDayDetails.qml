pragma ComponentBehavior: Bound
import QtQuick
import "./Calendar.js" as Calendar
import "../../ui/Theme.js" as Theme
import "../../ui"

Item {
  id: root
  property var forecast: null
  property bool loading: false
  readonly property var hours: Array.isArray(forecast?.hours) ? forecast.hours : []
  implicitHeight: hours.length > 0 ? 358 : 110

  function scrollHours(delta) {
    hourlyList.contentY = Math.max(0, Math.min(
      Math.max(0, hourlyList.contentHeight - hourlyList.height), hourlyList.contentY + delta * 44));
  }
  onForecastChanged: hourlyList.positionViewAtBeginning()

  Text {
    width: 30; height: 30
    text: Calendar.weatherIcon(root.forecast?.code)
    color: Calendar.weatherIconColor(root.forecast?.code)
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 24
    verticalAlignment: Text.AlignVCenter
  }
  Text {
    x: 36; height: 30; width: Math.max(0, parent.width - 132)
    text: Calendar.weatherDescription(root.forecast?.code)
    color: Theme.foreground
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 12
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
  }
  Text {
    anchors.right: parent.right
    height: 30
    text: Calendar.temperatureRange(root.forecast)
    color: Theme.sideWeather
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 12
    verticalAlignment: Text.AlignVCenter
  }

  Row {
    y: 38; width: parent.width; height: 22
    visible: root.hours.length > 0
    Repeater {
      model: [{label: "Heure", share: 0.14}, {label: "", share: 0.10},
        {label: "°C / ressenti", share: 0.25}, {label: "Pluie % / mm", share: 0.25},
        {label: "Vent / rafales", share: 0.26}]
      Text {
        required property var modelData
        width: root.width * modelData.share; height: 22
        text: modelData.label
        color: Theme.secondary
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 9
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  ListView {
    id: hourlyList
    objectName: "weatherHours"
    y: 62; width: parent.width; height: 264
    visible: root.hours.length > 0
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.hours
    delegate: Rectangle {
      id: hour
      required property var modelData
      required property int index
      objectName: "weatherHour" + index
      width: hourlyList.width; height: 44
      radius: 8
      border.width: 0
      // Reading guide, not a selected row: keep the same glass visible below
      // both stripes and reserve the stronger accent tint for selections.
      color: index % 2 === 0
        ? (GlassState.enabled ? Qt.alpha(Theme.foreground, 0.04) : Theme.surface)
        : "transparent"
      Text {
        x: 2; width: parent.width * 0.14 - 2; height: parent.height
        text: hour.modelData.time
        color: Theme.foreground
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 11
        verticalAlignment: Text.AlignVCenter
      }
      Text {
        x: parent.width * 0.14; width: parent.width * 0.10; height: parent.height
        text: Calendar.weatherIcon(hour.modelData.code)
        color: Calendar.weatherIconColor(hour.modelData.code)
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 20
        verticalAlignment: Text.AlignVCenter
      }
      Row {
        x: parent.width * 0.24
        Repeater {
          model: [
            {main: Calendar.weatherValue(hour.modelData.temperatureC, "°"),
              extra: Calendar.weatherValue(hour.modelData.apparentTemperatureC, "°"), share: 0.25},
            {main: Calendar.weatherValue(hour.modelData.precipitationProbability, "%"),
              extra: Calendar.weatherValue(hour.modelData.precipitationMm, " mm", 1), share: 0.25},
            {main: Calendar.weatherValue(hour.modelData.windKmh, " km/h"),
              extra: Calendar.weatherValue(hour.modelData.gustsKmh, " km/h"), share: 0.26}
          ]
          Column {
            required property var modelData
            y: 5; width: hour.width * modelData.share
            Text {
              text: parent.modelData.main
              color: Theme.foreground
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 11
              height: 18
            }
            Text {
              text: parent.modelData.extra
              color: Theme.secondary
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 10
              height: 16
            }
          }
        }
      }
    }
  }
  Rectangle {
    anchors.right: parent.right
    y: hourlyList.y + hourlyList.visibleArea.yPosition * hourlyList.height
    width: 3
    height: hourlyList.visibleArea.heightRatio * hourlyList.height
    radius: 1.5
    color: Theme.inactive
    visible: root.hours.length > 0 && hourlyList.contentHeight > hourlyList.height
  }
  Text {
    y: 336; width: parent.width; height: 16
    visible: root.hours.length > 0
    text: "Heures locales · pluie cumulée sur l’heure précédente"
    color: Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 9
    elide: Text.ElideRight
  }
  Text {
    objectName: "hourlyEmpty"
    y: 40; width: parent.width; height: 60
    visible: root.hours.length === 0
    text: root.loading ? "Chargement des prévisions horaires…"
      : root.forecast ? "Détail horaire indisponible pour ce jour."
      : "Ce jour est hors de la couverture météo disponible."
    wrapMode: Text.WordWrap
    color: Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 12
    verticalAlignment: Text.AlignVCenter
  }
}
