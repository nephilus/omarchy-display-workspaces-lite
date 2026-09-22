import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "display.workspaces.lite"
  ipcTarget: "display.workspaces.lite"
  property var workspaceWidget: null
  property var anchor: workspaceWidget
  readonly property var displayIcons: [
    { label: "\uf109  Laptop", value: "\uf109" },
    { label: "\uf108  Monitor", value: "\uf108" },
    { label: "\uf26c  Television", value: "\uf26c" },
    { label: "\uf120  Terminal", value: "\uf120" },
    { label: "\uf233  Server", value: "\uf233" },
    { label: "\uf11b  Gaming", value: "\uf11b" },
    { label: "\uf015  Home", value: "\uf015" },
    { label: "\uf0b1  Work", value: "\uf0b1" }
  ]

  function close() { controller.hide() }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchor
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(520))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(560))

    ScrollView {
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)
        Text {
          width: parent.width
          text: "Display workspace groups"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          width: parent.width
          text: "Names, icons, and menubar order save immediately. HyprMonCfg owns monitor layout and workspace rules."
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
        Repeater {
          model: root.workspaceWidget ? root.workspaceWidget.orderedMonitors() : []
          delegate: Rectangle {
            id: displayRow
            required property var modelData
            required property int index
            readonly property var display: root.workspaceWidget.displaySettings(modelData)
            width: content.width
            height: Style.space(112)
            color: "transparent"
            border.color: Color.foreground
            border.width: 1
            radius: Style.space(6)
            Column {
              x: Style.space(8); y: Style.space(7)
              width: parent.width - Style.space(16)
              spacing: Style.space(6)
              TextField {
                width: parent.width
                text: displayRow.display.name || displayRow.modelData.name
                maximumLength: 64
                selectByMouse: true
                onEditingFinished: {
                  var name = text, connector = displayRow.modelData.name
                  text = Qt.binding(function() { return displayRow.display.name || connector })
                  if (name.trim() !== (displayRow.display.name || connector))
                    root.workspaceWidget.renameDisplay(connector, name)
                }
              }
              Dropdown {
                id: iconPicker
                width: parent.width
                rowHeight: Style.space(30)
                value: displayRow.display.icon || "\uf108"
                options: root.displayIcons.some(function(choice) { return choice.value === value })
                  ? root.displayIcons : root.displayIcons.concat([{ label: value + "  Custom icon", value: value }])
                onChanged: function(icon) {
                  var connector = displayRow.modelData.name
                  Qt.callLater(function() {
                    iconPicker.value = Qt.binding(function() { return displayRow.display.icon || "\uf108" })
                    root.workspaceWidget.setDisplayIcon(connector, icon)
                  })
                }
              }
              RowLayout {
                width: parent.width
                Button {
                  text: "‹"
                  verticalPadding: Style.space(2)
                  enabled: displayRow.index > 0
                  opacity: enabled ? 1 : 0.45
                  onClicked: root.workspaceWidget.moveDisplayOrder(displayRow.modelData.name, -1)
                }
                Text {
                  Layout.fillWidth: true
                  text: displayRow.display.icon + " " + displayRow.modelData.name
                  color: Color.foreground
                  horizontalAlignment: Text.AlignHCenter
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Button {
                  text: "›"
                  verticalPadding: Style.space(2)
                  enabled: displayRow.index < root.workspaceWidget.orderedMonitors().length - 1
                  opacity: enabled ? 1 : 0.45
                  onClicked: root.workspaceWidget.moveDisplayOrder(displayRow.modelData.name, 1)
                }
              }
            }
          }
        }
        RowLayout {
          width: parent.width
          Item { Layout.fillWidth: true }
          Button { text: "Close"; verticalPadding: Style.space(4); onClicked: root.close() }
        }
      }
    }
  }
}
