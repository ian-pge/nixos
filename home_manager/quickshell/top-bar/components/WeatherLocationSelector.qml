pragma ComponentBehavior: Bound
import QtQuick
import "Theme.js" as Theme

FocusScope {
  id: root
  required property var weather
  signal closed()
  property int selectedIndex: 0
  readonly property var rows: weather.locationResults
  implicitHeight: 90 + Math.min(rows.length, 6) * 46

  function focusSearch() {
    searchInput.text = weather.locationQuery;
    searchInput.forceActiveFocus();
  }
  function moveSelection(delta) {
    if (rows.length === 0) return;
    selectedIndex = (selectedIndex + delta + rows.length) % rows.length;
    results.positionViewAtIndex(selectedIndex, ListView.Contain);
  }
  function choose(index) {
    if (rows[index]) weather.chooseLocation(rows[index]);
  }
  onEnabledChanged: {
    if (enabled) Qt.callLater(focusSearch);
  }
  Component.onCompleted: { if (enabled) Qt.callLater(focusSearch); }
  onRowsChanged: selectedIndex = 0

  Rectangle {
    width: parent.width; height: 34; radius: 7
    color: Theme.surfaceRaised
    TextInput {
      id: searchInput
      objectName: "locationSearchInput"
      x: 10; width: parent.width - 20; height: parent.height
      verticalAlignment: TextInput.AlignVCenter
      color: Theme.foreground
      selectionColor: Theme.sideWeather
      selectedTextColor: Theme.background
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 13
      clip: true
      maximumLength: 120
      onTextEdited: root.weather.setLocationQuery(text)
      Keys.onPressed: event => {
        const control = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab
            || (control && (event.key === Qt.Key_J || event.key === Qt.Key_N)))
          root.moveSelection(1);
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab
            || (control && (event.key === Qt.Key_K || event.key === Qt.Key_P)))
          root.moveSelection(-1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
          root.choose(root.selectedIndex);
        else if (event.key === Qt.Key_Escape)
          root.closed();
        else
          return;
        event.accepted = true;
      }
      Text {
        anchors.fill: parent
        visible: searchInput.text === ""
        text: "Ville ou code postal…"
        color: Theme.secondary
        font: searchInput.font
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
  Text {
    y: 42; width: parent.width; height: 18
    text: root.weather.locationSearchError || (root.weather.searchingLocations ? "Recherche…"
      : root.weather.locationQuery.trim().length < 2 ? "Saisis au moins deux caractères"
      : root.weather.locationResults.length === 0 ? "Aucune ville trouvée" : "Choisis la ville et sa région")
    color: root.weather.locationSearchError ? Theme.error : Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 10
    elide: Text.ElideRight
  }
  ListView {
    id: results
    objectName: "locationResults"
    y: 66; width: parent.width; height: Math.min(root.rows.length, 6) * 46
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.rows
    delegate: Rectangle {
      id: row
      required property int index
      required property var modelData
      width: results.width; height: 46; radius: 6
      color: index === root.selectedIndex ? Theme.surfaceRaised : "transparent"
      Text {
        x: 10; y: 4; width: parent.width - 20; height: 20
        text: row.modelData.name
        color: row.index === root.selectedIndex ? Theme.sideWeather : Theme.foreground
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 12
        font.bold: true
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      Text {
        x: 10; y: 25; width: parent.width - 20; height: 16
        text: [row.modelData.region, row.modelData.country].filter(Boolean).join(" · ")
        color: Theme.secondary
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 10
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.selectedIndex = row.index; root.choose(row.index); }
      }
    }
  }
}
