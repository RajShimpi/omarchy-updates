import QtQuick
import Quickshell
import Quickshell.Io

// Background check: `updates auto` checks when the cache is older than
// checkHours (~/.config/omarchy/updates.json, default 6) or was marked stale
// by an update, and sends one notification when updates show up that weren't
// there before. It never installs anything. Notifications live here, not in
// the bar widget: with two monitors there are two bars, but one service.
Item {
  id: root
  readonly property string dir: Qt.resolvedUrl("scripts/").toString().replace(/^file:\/\//, "")

  Process { id: auto; command: [root.dir + "updates", "auto"] }

  // Give the network a minute after login or a shell restart.
  Timer { interval: 60000; running: true; onTriggered: if (!auto.running) auto.running = true }
  Timer { interval: 1800000; repeat: true; running: true; onTriggered: if (!auto.running) auto.running = true }
}
