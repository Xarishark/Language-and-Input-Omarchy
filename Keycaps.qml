import QtQuick
import qs.Ui
import qs.Commons

Row {
  id: root
  property var keys: []
  property real fontSize: Style.font.title
  spacing: Style.spacing.controlGap
  Repeater {
    model: root.keys
    Row {
      required property string modelData
      required property int index
      spacing: Style.spacing.controlGap
      Text {
        visible: index > 0
        text: "+"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: root.fontSize
        anchors.verticalCenter: parent.verticalCenter
      }
      BorderSurface {
        implicitWidth: label.implicitWidth + Style.spacing.controlPaddingX * 2
        implicitHeight: label.implicitHeight + Style.spacing.controlPaddingY * 2
        borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
        radius: Style.cornerRadius
        color: Color.menu.selectedBackground
        Text {
          id: label
          anchors.centerIn: parent
          text: modelData
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: root.fontSize
        }
      }
    }
  }
}
