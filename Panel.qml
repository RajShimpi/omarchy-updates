import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Updates: what scripts/updates found for Omarchy, system packages, AUR
// apps, mise dev tools, shell plugins and themes. Nothing updates until the
// user confirms in the card below; updates then run in a floating terminal
// (sudo password, Omarchy's own prompts, plugin diffs with yes/no).
//
// This is a bar widget, so with two monitors there are two of it. Neither
// sends notifications (the service does); they only share the cache file.
Panel {
  id: root
  moduleName: "techspawn.updates"
  ipcTarget: "techspawn.updates"
  manageIpc: true

  readonly property string dir: Qt.resolvedUrl("scripts/").toString().replace(/^file:\/\//, "")
  readonly property string cache: Quickshell.env("HOME") + "/.cache/omarchy/updates.json"
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color warning: Commons.Color.urgent
  readonly property string font: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property string pluginMgr: "io.github.bonesgit.omarchy-ultimate-plugin-mgr"

  property var report: ({ at: 0, total: 0, omarchy: { available: false, lines: [] }, sections: [] })
  property string expanded: ""
  // { whats: ["system"], title, lines: [], more, note } while the confirmation card is up.
  property var pending: null
  // Seconds; ticks so "checked … ago" and the time limits below stay current.
  property real now: Date.now() / 1000

  readonly property int total: report.total || 0
  readonly property bool omarchyUpdate: !!(report.omarchy && report.omarchy.available)
  // An update started from this panel is running in a terminal.
  readonly property bool running: !!report.running && now - (report.runningSince || 0) < 10800
  readonly property bool checking: checkProc.running
    || (!!report.checking && now - (report.checkingSince || 0) < 300)
  readonly property bool busy: checking || running

  function g(cp) { return String.fromCodePoint(cp) }

  readonly property var icons: ({
    system: 0xF03D6, aur: 0xF003B, mise: 0xF1064, plugins: 0xF0431, themes: 0xF03D8
  })
  readonly property var units: ({
    system: ["package", "packages"], aur: ["app", "apps"], mise: ["tool", "tools"],
    plugins: ["plugin", "plugins"], themes: ["theme", "themes"]
  })
  readonly property var notes: ({
    system: "Runs Omarchy's full update: a snapshot first, then system packages, AUR apps and dev tools, then migrations. Omarchy asks once more before it starts, then for your password, and offers a reboot if the kernel changed.",
    aur: "Rebuilds the AUR apps with yay. It asks for your password.",
    mise: "Updates the dev tools that mise manages.",
    plugins: "Each plugin shows its code changes in the terminal and asks yes or no before it updates. Changes you made to a plugin yourself are kept when they still fit.",
    themes: "Pulls the git themes you installed (fast-forward only)."
  })

  function counted(id, n) {
    var u = units[id] || ["update", "updates"]
    return n + " " + (n === 1 ? u[0] : u[1])
  }

  function section(id) {
    var list = report.sections || []
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
  }

  function count(id) {
    var s = section(id)
    return s && s.items ? s.items.length : 0
  }

  function ago(ts) {
    if (!ts) return "never"
    var s = Math.max(0, now - ts)
    return s < 60 ? "just now" : s < 3600 ? Math.floor(s / 60) + " min ago" : s < 86400 ? Math.floor(s / 3600) + " h ago" : Math.floor(s / 86400) + " d ago"
  }

  function shortList(names, max) {
    if (names.length <= max) return names.join(", ")
    return names.slice(0, max).join(", ") + " and " + (names.length - max) + " more"
  }

  // Plugins whose own uncommitted changes clash with their update.
  function clashing() {
    var s = section("plugins")
    if (!s || !s.items) return []
    return s.items.filter(function(it) { return it.localChanges === "clash" || it.localChanges === "unknown" })
      .map(function(it) { return it.label || it.name })
  }

  function localNote(it) {
    var files = (it.localFiles || []).join(", ") || "this plugin"
    if (it.localChanges === "kept") return "Your changes to " + files + " are kept"
    if (it.localChanges === "upstream") return "Your changes to " + files + " are already in this version"
    if (it.localChanges === "clash") return "Your changes to " + files + " clash with this update; it asks before setting them aside"
    if (it.localChanges === "unknown") return "Has your own changes; it asks before setting them aside"
    return ""
  }

  function runCheck() { if (!checkProc.running && !running) checkProc.running = true }

  function ask(id) {
    if (busy) return
    var clash = clashing()
    if (id === "all") {
      var lines = [], steps = []
      if (omarchyUpdate) lines.push("Omarchy: " + report.omarchy.lines.join(", "))
      ;(report.sections || []).forEach(function(s) {
        if (s.items && s.items.length) lines.push(s.title + ": " + counted(s.id, s.items.length))
      })
      if (count("plugins")) steps.push("plugins first (each one shows its changes and asks)")
      if (count("themes")) steps.push("themes")
      if (omarchyUpdate || count("system") || count("aur") || count("mise"))
        steps.push("Omarchy's full update with a snapshot, system packages, AUR apps and dev tools (it asks for your password)")
      var note = steps.length ? "Runs " + steps.join(", then ") + "." : ""
      if (clash.length) note += " " + shortList(clash, 2) + (clash.length === 1 ? " has" : " have") + " local changes that clash with the update; it asks before setting them aside."
      pending = { whats: ["all"], title: "Update everything?", lines: lines, more: 0, note: note }
    } else {
      var s = section(id)
      var items = s && s.items ? s.items : []
      var extra = id === "plugins" && clash.length
        ? " " + shortList(clash, 2) + (clash.length === 1 ? " has" : " have") + " local changes that clash with the update; it asks before setting them aside."
        : ""
      pending = {
        whats: [id],
        title: "Update " + (s ? s.title.toLowerCase() : id) + "?",
        lines: items.slice(0, 6).map(function(it) { return (it.label || it.name) + "  " + (it.from || "") + " → " + (it.to || "") }),
        more: Math.max(0, items.length - 6),
        note: (notes[id] || "") + extra
      }
    }
  }

  function confirmUpdate() {
    if (!pending) return
    var whats = pending.whats.filter(function(w) { return /^[a-z]+(:[A-Za-z0-9][A-Za-z0-9._-]*)?$/.test(w) })
    pending = null
    if (!whats.length || busy) return
    // The wrapper runs this through bash -c, so quote the script path.
    var script = "'" + (root.dir + "updates").replace(/'/g, "'\\''") + "'"
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", script + " run " + whats.join(" ")])
    root.close()
  }

  onOpenedChanged: {
    if (opened) {
      now = Date.now() / 1000
      pending = null
      // A stale list is worse than a short wait.
      if (!running && (report.stale || now - (report.at || 0) > 1800)) runCheck()
    }
  }

  Timer {
    interval: root.opened ? 15000 : 60000
    running: true
    repeat: true
    onTriggered: root.now = Date.now() / 1000
  }

  FileView {
    path: root.cache
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.report = JSON.parse(text()) } catch (e) {}
      root.now = Date.now() / 1000
    }
  }

  Process { id: checkProc; command: [root.dir + "updates", "check"] }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.g(0xF06B0)
    dimmed: root.total === 0 && !root.busy
    tooltipText: root.running ? "Updating in a terminal…"
      : root.checking ? "Checking for updates…"
      : root.total > 0 ? root.total + " update" + (root.total === 1 ? "" : "s") + " available"
      : "Everything is up to date"
    onPressed: function(b) { root.toggle() }

    Rectangle {
      visible: root.total > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: -2
      width: Math.max(height, badge.implicitWidth + 3)
      height: badge.implicitHeight
      radius: height / 2
      color: root.omarchyUpdate ? Commons.Color.urgent : root.accent
      Text {
        id: badge
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.total > 99 ? "99+" : String(root.total)
        color: root.bar ? root.bar.background : Commons.Color.background
        font.family: root.font
        font.pixelSize: Math.max(7, Math.round(Style.font.caption * 0.7))
        font.bold: true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.pending ? root.pending = null : root.close()
      onReturnRequested: if (root.pending) root.confirmUpdate()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" && !root.pending) root.runCheck() }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Header ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(hero.implicitHeight, heroButtons.implicitHeight)
          Row {
            id: hero
            spacing: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              text: root.g(0xF06B0)
              color: root.total > 0 ? root.accent : root.fg
              font.family: root.font; font.pixelSize: Style.font.display
              anchors.verticalCenter: parent.verticalCenter
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text { textFormat: Text.PlainText; text: "Updates"; color: root.fg; font.family: root.font; font.pixelSize: Style.font.title; font.bold: true }
              Text {
                textFormat: Text.PlainText
                text: (root.running ? "Updating in a terminal…"
                  : root.checking ? "Checking…"
                  : (root.total > 0 ? root.total + " available" : "All up to date") + " · checked " + root.ago(root.report.at)).toUpperCase()
                color: Qt.darker(root.fg, 1.4); font.family: root.font; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.2
              }
            }
          }
          Row {
            id: heroButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Button {
              iconText: root.g(0xF0450); text: root.checking ? "Checking…" : "Check now"
              iconSpinning: root.checking
              fontSize: Style.font.caption
              foreground: root.fg; fontFamily: root.font; bordered: true
              enabled: !root.busy
              onClicked: root.runCheck()
            }
            Button {
              visible: root.total > 0
              iconText: root.g(0xF06B0); text: "Update all…"
              fontSize: Style.font.caption
              foreground: root.accent; fontFamily: root.font; bordered: true
              enabled: !root.busy
              onClicked: root.ask("all")
            }
          }
        }

        // ---------- An update is running ----------
        Rectangle {
          visible: root.running
          width: parent.width
          implicitHeight: runningRow.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
          Row {
            id: runningRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)
            Text { textFormat: Text.PlainText; text: root.g(0xF0997); color: root.accent; font.family: root.font; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
            Text {
              width: parent.width - Style.space(30)
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "An update is running in a terminal. This list refreshes when it finishes."
              color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }

        // ---------- Confirmation ----------
        Rectangle {
          visible: !!root.pending
          width: parent.width
          implicitHeight: confirmCol.implicitHeight + Style.space(24)
          radius: Style.cornerRadius
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
          border.width: Math.max(1, Style.normalBorderWidth)
          border.color: root.accent

          Column {
            id: confirmCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              text: root.pending ? root.pending.title : ""
              color: root.fg; font.family: root.font; font.pixelSize: Style.font.body; font.bold: true
            }
            Repeater {
              model: root.pending ? root.pending.lines : []
              delegate: Text {
                required property var modelData
                width: confirmCol.width
                textFormat: Text.PlainText
                text: "· " + modelData
                elide: Text.ElideRight
                color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption
              }
            }
            Text {
              visible: !!root.pending && root.pending.more > 0
              textFormat: Text.PlainText
              text: root.pending ? "· and " + root.pending.more + " more" : ""
              color: Qt.darker(root.fg, 1.4); font.family: root.font; font.pixelSize: Style.font.caption
            }
            Text {
              width: confirmCol.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: (root.pending && root.pending.note ? root.pending.note + " " : "") + "It runs in a terminal so you can watch it."
              color: Qt.darker(root.fg, 1.4); font.family: root.font; font.pixelSize: Style.font.caption
            }
            Row {
              spacing: Style.space(8)
              Button {
                iconText: root.g(0xF0E1E); text: "Yes, update"
                fontSize: Style.font.caption
                foreground: root.accent; fontFamily: root.font; bordered: true
                onClicked: root.confirmUpdate()
              }
              Button {
                text: "Cancel"
                fontSize: Style.font.caption
                foreground: root.fg; fontFamily: root.font; bordered: true
                onClicked: root.pending = null
              }
            }
          }
        }

        // ---------- Omarchy ----------
        Rectangle {
          visible: root.omarchyUpdate
          width: parent.width
          implicitHeight: omarchyRow.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)
          Row {
            id: omarchyRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)
            Text { textFormat: Text.PlainText; text: root.g(0xF303); color: root.accent; font.family: root.font; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
            Column {
              width: parent.width - Style.space(30) - whatsNew.width - Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              Text { textFormat: Text.PlainText; text: "New Omarchy version"; color: root.fg; font.family: root.font; font.pixelSize: Style.font.bodySmall; font.bold: true }
              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.omarchyUpdate ? root.report.omarchy.lines.join(" · ") : ""
                color: Qt.darker(root.fg, 1.4); font.family: root.font; font.pixelSize: Style.font.caption
              }
            }
            Button {
              id: whatsNew
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.g(0xF03CC); text: "What's new"
              fontSize: Style.font.caption
              foreground: root.fg; fontFamily: root.font; bordered: true
              onClicked: { Quickshell.execDetached(["xdg-open", "https://github.com/omacom/omarchy/releases/latest"]); root.close() }
            }
          }
        }

        // ---------- Sections ----------
        Column {
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: (root.report.sections || []).filter(function(s) { return s.id !== "themes" || (s.checked || 0) > 0 })
            delegate: Rectangle {
              id: sec
              required property var modelData
              readonly property int count: modelData.items ? modelData.items.length : 0
              readonly property var attention: modelData.attention || []
              readonly property bool expandable: count > 0 || attention.length > 0
              readonly property bool open: root.expanded === modelData.id && expandable
              readonly property bool failed: !!modelData.error
              width: parent.width
              implicitHeight: secCol.implicitHeight + Style.space(12)
              radius: Style.cornerRadius
              color: area.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.04)

              MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: sec.expandable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.expanded = sec.open ? "" : sec.modelData.id
              }

              Column {
                id: secCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(6)
                anchors.leftMargin: Style.space(10)
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  implicitHeight: Math.max(secHead.implicitHeight, secButton.implicitHeight)
                  Row {
                    id: secHead
                    anchors.left: parent.left
                    anchors.right: secButton.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)
                    Text {
                      textFormat: Text.PlainText
                      text: root.g(sec.failed ? 0xF05D6 : (root.icons[sec.modelData.id] || 0xF06B0))
                      color: sec.failed ? root.warning : sec.count > 0 ? root.accent : Qt.darker(root.fg, 1.4)
                      font.family: root.font; font.pixelSize: Style.font.body
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                      width: parent.width - Style.space(30)
                      anchors.verticalCenter: parent.verticalCenter
                      Text {
                        textFormat: Text.PlainText
                        text: sec.modelData.title + (sec.expandable ? "  " + root.g(sec.open ? 0xF0140 : 0xF0142) : "")
                        color: root.fg; font.family: root.font; font.pixelSize: Style.font.bodySmall; font.bold: true
                      }
                      Text {
                        width: parent.width
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        color: sec.failed ? root.warning : Qt.darker(root.fg, 1.4)
                        font.family: root.font; font.pixelSize: Style.font.caption
                        text: {
                          var m = sec.modelData
                          if (sec.failed) return m.error
                          var t = sec.count > 0 ? root.counted(m.id, sec.count) + " to update" : "Up to date"
                          if (m.checked !== undefined && m.checked !== null) t += " · " + m.checked + " checked"
                          if (m.local) t += " · " + m.local + " not from git"
                          if (sec.attention.length) t += " · " + sec.attention.length + " to update by hand"
                          var errs = m.errors || []
                          if (errs.length) t += " · couldn't reach " + root.shortList(errs, 2)
                          return t
                        }
                      }
                    }
                  }
                  Button {
                    id: secButton
                    visible: sec.count > 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Update…"
                    fontSize: Style.font.caption
                    foreground: root.fg; fontFamily: root.font; bordered: true
                    enabled: !root.busy
                    onClicked: root.ask(sec.modelData.id)
                  }
                }

                // Item list, capped so a big system update can't push the
                // panel off the screen.
                Repeater {
                  model: sec.open ? sec.modelData.items.slice(0, 12) : []
                  delegate: Column {
                    id: itemCol
                    required property var modelData
                    readonly property string localText: root.localNote(modelData)
                    width: secCol.width
                    Item {
                      width: parent.width
                      implicitHeight: itemName.implicitHeight
                      Text {
                        id: itemName
                        x: Style.space(28)
                        width: parent.width - x - itemVersion.width - Style.space(8)
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: (itemCol.modelData.label || itemCol.modelData.name)
                          + (itemCol.modelData.dirty && !itemCol.localText ? "  (local changes)" : "")
                        color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption
                      }
                      Text {
                        id: itemVersion
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(8)
                        textFormat: Text.PlainText
                        text: itemCol.modelData.behind ? itemCol.modelData.behind + " commit" + (itemCol.modelData.behind === 1 ? "" : "s")
                          : (itemCol.modelData.from || "") + " → " + (itemCol.modelData.to || "")
                        color: Qt.darker(root.fg, 1.3); font.family: root.font; font.pixelSize: Style.font.caption
                      }
                    }
                    Text {
                      visible: !!(itemCol.modelData.subjects && itemCol.modelData.subjects.length)
                      x: Style.space(40)
                      width: parent.width - x - Style.space(8)
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: itemCol.modelData.subjects ? itemCol.modelData.subjects.join(" · ") : ""
                      color: Qt.darker(root.fg, 1.6); font.family: root.font; font.pixelSize: Style.font.caption
                    }
                    Text {
                      visible: itemCol.localText !== ""
                      x: Style.space(40)
                      width: parent.width - x - Style.space(8)
                      wrapMode: Text.Wrap
                      textFormat: Text.PlainText
                      text: itemCol.localText
                      color: itemCol.modelData.localChanges === "clash" || itemCol.modelData.localChanges === "unknown"
                        ? root.warning : Qt.darker(root.fg, 1.4)
                      font.family: root.font; font.pixelSize: Style.font.caption
                    }
                  }
                }
                Text {
                  visible: sec.open && sec.count > 12
                  x: Style.space(28)
                  textFormat: Text.PlainText
                  text: "and " + (sec.count - 12) + " more"
                  color: Qt.darker(root.fg, 1.6); font.family: root.font; font.pixelSize: Style.font.caption
                }

                // Plugins that can't simply move forward: local commits, or
                // upstream rewrote its history.
                Repeater {
                  model: sec.open ? sec.attention : []
                  delegate: Text {
                    required property var modelData
                    x: Style.space(28)
                    width: secCol.width - x - Style.space(8)
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: root.g(0xF062C) + "  " + (modelData.label || modelData.name) + ": " + modelData.behind + " new upstream, "
                      + modelData.ahead + " local commit" + (modelData.ahead === 1 ? "" : "s") + ". Update it by hand."
                    color: root.warning; font.family: root.font; font.pixelSize: Style.font.caption
                  }
                }

                Button {
                  visible: sec.open && sec.modelData.id === "plugins" && sec.count > 0 && !!root.report.pluginManager
                  x: Style.space(28)
                  iconText: root.g(0xF0D9A); text: "Security-scan them in Plugin Manager"
                  fontSize: Style.font.caption
                  foreground: root.fg; fontFamily: root.font; bordered: true
                  onClicked: { Quickshell.execDetached(["omarchy-shell", "-q", root.pluginMgr, "open"]); root.close() }
                }
              }
            }
          }
        }

        Text {
          visible: (root.report.sections || []).length === 0 && !root.checking
          textFormat: Text.PlainText
          text: "No check has run yet."
          color: Qt.darker(root.fg, 1.4); font.family: root.font; font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: "Nothing updates without your OK. Checks run every few hours; you get a notification when something new shows up."
          color: Qt.darker(root.fg, 1.8); font.family: root.font; font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
