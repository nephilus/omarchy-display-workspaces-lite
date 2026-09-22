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
  property string selectedKey: ""
  property bool forgetArmed: false
  readonly property var rememberedOptions: workspaceWidget ? workspaceWidget.rememberedDisplayOptions() : []
  readonly property var selectedEntry: workspaceWidget ? workspaceWidget.rememberedDisplay(selectedKey) : null
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
  function ensureSelection() {
    if (!rememberedOptions.length) {
      selectedKey = ""
      forgetArmed = false
      return
    }
    var exists = rememberedOptions.some(function(option) { return option.value === selectedKey })
    if (!exists) selectedKey = rememberedOptions[0].value
  }
  function selectRemembered(key) {
    selectedKey = key
    forgetArmed = false
  }
  function forgetSelected() {
    if (!selectedEntry) return
    if (!forgetArmed) {
      forgetArmed = true
      return
    }
    if (workspaceWidget.forgetRememberedDisplay(selectedKey)) {
      selectedKey = ""
      forgetArmed = false
      Qt.callLater(ensureSelection)
    }
  }

  onOpenedChanged: if (opened) ensureSelection()
  onRememberedOptionsChanged: if (opened) ensureSelection()

  KeyboardPanel {
    id: popup
    anchorItem: root.anchor
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(600))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(500))

    ScrollView {
      id: contentScroll
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      Column {
        id: content
        width: Math.max(1, contentScroll.width - contentScroll.leftPadding - contentScroll.rightPadding - Style.space(2))
        spacing: Style.space(12)

        Text {
          width: parent.width
          text: "Display Order"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        ScrollView {
          width: parent.width
          height: Style.space(108)
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AsNeeded
          ScrollBar.vertical.policy: ScrollBar.AlwaysOff
          Row {
            spacing: Style.space(8)
            Repeater {
              model: root.workspaceWidget ? root.workspaceWidget.orderedMonitors() : []
              delegate: Rectangle {
                id: displayCard
                required property var modelData
                required property int index
                readonly property var display: root.workspaceWidget.displaySettings(modelData)
                width: Style.space(150)
                height: Style.space(92)
                color: Color.popups.background
                border.color: Color.foreground
                border.width: 1
                radius: Style.space(6)
                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(5)
                  Text {
                    width: parent.width
                    text: (displayCard.index + 1) + "  " + (displayCard.display.icon || "\uf108")
                      + "  " + (displayCard.display.name || displayCard.modelData.name)
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: displayCard.modelData.name
                    color: Qt.darker(Color.foreground, 1.35)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                  Item { width: 1; height: Style.space(3) }
                  RowLayout {
                    width: parent.width
                    spacing: Style.space(5)
                    Button {
                      text: "← Left"
                      Layout.fillWidth: true
                      verticalPadding: Style.space(2)
                      enabled: displayCard.index > 0
                      opacity: enabled ? 1 : 0.45
                      onClicked: root.workspaceWidget.moveDisplayOrder(displayCard.modelData.name, -1)
                    }
                    Button {
                      text: "Right →"
                      Layout.fillWidth: true
                      verticalPadding: Style.space(2)
                      enabled: displayCard.index < root.workspaceWidget.orderedMonitors().length - 1
                      opacity: enabled ? 1 : 0.45
                      onClicked: root.workspaceWidget.moveDisplayOrder(displayCard.modelData.name, 1)
                    }
                  }
                }
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.darker(Color.foreground, 1.8) }
        Text {
          width: parent.width
          text: "Saved Displays"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Dropdown {
          width: parent.width
          label: "Display"
          value: root.selectedKey
          options: root.rememberedOptions
          onChanged: function(key) { root.selectRemembered(key) }
        }

        Rectangle {
          width: parent.width
          height: root.selectedEntry ? Style.space(155) : Style.space(52)
          color: "transparent"
          border.color: Color.foreground
          border.width: 1
          radius: Style.space(6)

          Text {
            anchors.centerIn: parent
            visible: !root.selectedEntry
            text: "No remembered displays"
            color: Qt.darker(Color.foreground, 1.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(8)
            spacing: Style.space(6)
            visible: !!root.selectedEntry
            property string entryKey: root.selectedKey
            onEntryKeyChanged: {
              var entry = root.selectedEntry
              nameInput.text = entry ? entry.name || entry.connector : ""
              iconPicker.value = entry ? entry.icon || "\uf108" : "\uf108"
            }

            Text {
              width: parent.width
              text: root.selectedEntry
                ? "Connector: " + (root.selectedEntry.connector || "Not recorded")
                  + "  ·  " + (root.workspaceWidget.connectedConnectorFor(root.selectedEntry) ? "Connected" : "Disconnected")
                : ""
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            TextField {
              id: nameInput
              width: parent.width
              maximumLength: 64
              selectByMouse: true
              placeholderText: "Display name"
            }
            Dropdown {
              id: iconPicker
              width: parent.width
              label: "Icon"
              rowHeight: Style.space(30)
              options: root.displayIcons.some(function(choice) { return choice.value === value })
                ? root.displayIcons : root.displayIcons.concat([{ label: value + "  Custom icon", value: value }])
            }
            Row {
              width: parent.width
              spacing: Style.space(10)
              Button {
                text: "Save changes"
                verticalPadding: Style.space(3)
                enabled: nameInput.text.trim().length > 0
                onClicked: {
                  root.workspaceWidget.updateRememberedDisplay(root.selectedKey, nameInput.text, iconPicker.value)
                  root.forgetArmed = false
                }
              }
              Button {
                text: root.forgetArmed ? "Confirm forget" : "Forget association"
                verticalPadding: Style.space(3)
                onClicked: root.forgetSelected()
              }
            }
            Text {
              width: parent.width
              visible: root.forgetArmed
              text: "This removes only the saved name, icon, connector association, and order."
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
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
