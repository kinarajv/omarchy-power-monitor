import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"

  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var hardware: ({})
  property var cpuHistory: []
  property var memoryHistory: []
  property int historyLimit: setting("historyLimit", 30)
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  readonly property bool showPercentage: setting("showPercentage", false) === true

  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Color.foreground
  }

  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function pluginFile(relative) {
    var url = String(Qt.resolvedUrl(relative))
    if (url.indexOf("file://") === 0) url = url.slice(7)
    try { url = decodeURIComponent(url) } catch (e) {}
    return url
  }
  readonly property string hardwareScript: pluginFile("hardware-stats")

  readonly property var childEnvironment: ({
    "HOME": null,
    "PATH": "/usr/bin:/bin",
    "LANG": "C.UTF-8",
    "LC_ALL": "C.UTF-8"
  })

  function refresh() {
    if (!batteryPresent || !root.opened) return

    if (!batteryProc.running) {
      batteryProc.buffer = ""
      batteryProc.lines = 0
      batteryProc.running = true
    }
    if (!profilesProc.running) {
      profilesProc.buffer = ""
      profilesProc.lines = 0
      profilesProc.running = true
    }
    if (!systemProc.running) {
      systemProc.buffer = ""
      systemProc.lines = 0
      systemProc.running = true
    }
    if (!hardwareProc.running) {
      hardwareProc.buffer = ""
      hardwareProc.lines = 0
      hardwareProc.running = true
    }
    pollWatchdog.restart()
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)

    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)

    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function appendHistory(history, value) {
    var next = history.slice()
    next.push(Math.max(0, Math.min(100, Number(value) || 0)))
    if (next.length > historyLimit) next.shift()
    return next
  }

  function updateHardware(raw) {
    var lines = String(raw || "").trim().split("\n")
    var next = {}
    for (var i = 0; i < lines.length; i++) {
      var pos = lines[i].indexOf("=")
      if (pos <= 0) continue
      next[lines[i].slice(0, pos)] = lines[i].slice(pos + 1)
    }
    hardware = next
    cpuHistory = appendHistory(cpuHistory, String(next.cpu_percent || "0").replace("%", ""))
    memoryHistory = appendHistory(memoryHistory, next.ram_percent)
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["/usr/bin/omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
    actionWatchdog.restart()
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    } else {
      if (batteryProc.running) batteryProc.running = false
      if (profilesProc.running) profilesProc.running = false
      if (systemProc.running) systemProc.running = false
      if (hardwareProc.running) hardwareProc.running = false
      pollWatchdog.stop()
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["/usr/bin/omarchy-battery-status", "--shell"]
    environment: root.childEnvironment
    clearEnvironment: true
    property string buffer: ""
    property int bytesRead: 0
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        batteryProc.bytesRead += chunk.length
        if (batteryProc.bytesRead > 2048) {
          batteryProc.running = false
          return
        }
        batteryProc.buffer += chunk
      }
    }
    onExited: {
      root.updateKeyValue(batteryProc.buffer, "battery")
      batteryProc.buffer = ""
      batteryProc.bytesRead = 0
    }
  }

  Process {
    id: profilesProc
    command: ["/usr/bin/omarchy-powerprofiles-list", "--active-state"]
    environment: root.childEnvironment
    clearEnvironment: true
    property string buffer: ""
    property int bytesRead: 0
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        profilesProc.bytesRead += chunk.length
        if (profilesProc.bytesRead > 1024) {
          profilesProc.running = false
          return
        }
        profilesProc.buffer += chunk
      }
    }
    onExited: {
      root.updateProfiles(profilesProc.buffer)
      profilesProc.buffer = ""
      profilesProc.bytesRead = 0
    }
  }

  Process {
    id: systemProc
    command: ["/usr/bin/omarchy-system-stats"]
    environment: root.childEnvironment
    clearEnvironment: true
    property string buffer: ""
    property int bytesRead: 0
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        systemProc.bytesRead += chunk.length
        if (systemProc.bytesRead > 1024) {
          systemProc.running = false
          return
        }
        systemProc.buffer += chunk
      }
    }
    onExited: {
      root.updateKeyValue(systemProc.buffer, "system")
      systemProc.buffer = ""
      systemProc.bytesRead = 0
    }
  }

  Process {
    id: hardwareProc
    command: ["/usr/bin/python3", "-I", root.hardwareScript]
    environment: root.childEnvironment
    clearEnvironment: true
    property string buffer: ""
    property int bytesRead: 0
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        hardwareProc.bytesRead += chunk.length
        if (hardwareProc.bytesRead > 2048) {
          hardwareProc.running = false
          return
        }
        hardwareProc.buffer += chunk
      }
    }
    onExited: {
      root.updateHardware(hardwareProc.buffer)
      hardwareProc.buffer = ""
      hardwareProc.bytesRead = 0
    }
  }

  Process {
    id: actionProc
    environment: root.childEnvironment
    clearEnvironment: true
    onExited: root.refresh()
  }

  Timer {
    id: actionWatchdog
    interval: 4000
    repeat: false
    onTriggered: {
      if (actionProc.running) actionProc.running = false
    }
  }

  Timer {
    id: pollWatchdog
    interval: 3500
    repeat: false
    onTriggered: {
      if (batteryProc.running) batteryProc.running = false
      if (profilesProc.running) profilesProc.running = false
      if (systemProc.running) systemProc.running = false
      if (hardwareProc.running) hardwareProc.running = false
    }
  }

  Timer { interval: setting("refreshInterval", 5000); running: root.opened; repeat: true; onTriggered: root.refresh() }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
      : root.batteryIcon()
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.batteryInfo.percentage || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.batteryInfo.threshold || "-") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "CPU"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Usage"; value: root.hardware.cpu_percent || "—" }
              InfoPair { label: "Temperature"; value: root.hardware.cpu_temp || "—" }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Power"; value: root.hardware.cpu_watt || "—" }
            }
          }

          HistoryGraph {
            width: parent.width
            values: root.cpuHistory
            foreground: root.bar.foreground
          }

          PanelSectionHeader {
            text: "MEMORY"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(20)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap
              InfoPair { label: "Total RAM"; value: root.hardware.ram_total || "—" }
              InfoPair { label: "Free RAM"; value: root.hardware.ram_free || "—" }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              InfoPair { label: "Used RAM"; value: root.hardware.ram_used || "—" }
            }
          }

          HistoryGraph {
            width: parent.width
            values: root.memoryHistory
            foreground: root.bar.foreground
            autoScale: true
          }
        }
      }
    }
  }

  component HistoryGraph: Item {
    id: graph
    property var values: []
    property color foreground: "white"
    property bool autoScale: false
    height: 52

    onValuesChanged: canvas.requestPaint()
    onForegroundChanged: canvas.requestPaint()

    Canvas {
      id: canvas
      anchors.fill: parent

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        ctx.fillStyle = Qt.rgba(graph.foreground.r, graph.foreground.g, graph.foreground.b, 0.045)
        ctx.fillRect(0, 0, width, height)

        ctx.strokeStyle = Qt.rgba(graph.foreground.r, graph.foreground.g, graph.foreground.b, 0.10)
        ctx.lineWidth = 1
        for (var row = 1; row < 4; row++) {
          var gy = Math.round(height * row / 4) + 0.5
          ctx.beginPath()
          ctx.moveTo(0, gy)
          ctx.lineTo(width, gy)
          ctx.stroke()
        }

        if (!graph.values || graph.values.length === 0) return
        var step = graph.values.length > 1 ? width / (graph.values.length - 1) : width
        var minimum = 0
        var maximum = 100
        if (graph.autoScale && graph.values.length > 1) {
          minimum = Math.min.apply(Math, graph.values)
          maximum = Math.max.apply(Math, graph.values)
          var padding = Math.max(2, (maximum - minimum) * 0.25)
          minimum = Math.max(0, minimum - padding)
          maximum = Math.min(100, maximum + padding)
        }
        var range = Math.max(1, maximum - minimum)
        var points = []
        for (var i = 0; i < graph.values.length; i++)
          points.push({ x: i * step, y: height - ((Number(graph.values[i]) - minimum) / range) * height })

        ctx.beginPath()
        ctx.moveTo(points[0].x, height)
        for (var p = 0; p < points.length; p++) ctx.lineTo(points[p].x, points[p].y)
        ctx.lineTo(points[points.length - 1].x, height)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(graph.foreground.r, graph.foreground.g, graph.foreground.b, 0.12)
        ctx.fill()

        ctx.beginPath()
        ctx.moveTo(points[0].x, points[0].y)
        for (var j = 1; j < points.length; j++) ctx.lineTo(points[j].x, points[j].y)
        ctx.strokeStyle = graph.foreground
        ctx.lineWidth = 1.5
        ctx.stroke()
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
