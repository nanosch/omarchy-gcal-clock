import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  // Local noon, so a first of the month with no midnight (Havana, April 2012)
  // still names its own month; UTC would name the previous one west of Greenwich.
  readonly property date viewDate: new Date(viewYear, viewMonth, 1, 12)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)


  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // Compact grid (was 52/34/32/14) to make room for the day agenda.
  readonly property int cellWidth: Style.space(34)
  readonly property int cellHeight: Style.space(30)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(22)
  readonly property int gutterWidth: Style.space(8)
  readonly property int agendaWidth: Style.space(340)

  // ---- Day agenda (Google Calendar via the `gws` CLI).
  //      The selected day defaults to today; clicking a day cell moves it.
  property date selectedDate: new Date()
  readonly property string selectedKey: Model.keyForDate(selectedDate)
  property var eventsByDay: ({})
  property var agendaErrors: ({})
  property string loadingKey: ""
  property string pendingKey: ""
  readonly property bool agendaLoading: loadingKey === selectedKey && selectedKey !== ""
  readonly property var agendaEvents: eventsByDay[selectedKey] || []
  readonly property bool agendaLoaded: eventsByDay[selectedKey] !== undefined
  readonly property string agendaError: agendaErrors[selectedKey] || ""
  // gws login missing/expired/revoked: show reconnect instructions instead
  // of the agenda until a request succeeds again.
  property bool authFailed: false
  readonly property string reconnectScript: Qt.resolvedUrl("gws-reconnect.sh").toString().replace("file://", "")

  function reconnect() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", root.reconnectScript])
    root.close()
  }

  function looksLikeAuthError(text) {
    return /error\[auth\]|authError|invalid_grant|"code":\s*401|No credentials|Token has been expired or revoked|unauthorized_client/i.test(text)
  }
  property date now: new Date()

  function selectDay(year, month, day) {
    root.selectedDate = new Date(year, month, day, 12)
    root.loadAgenda(false)
  }

  // Previous/next day; the month grid follows when the day leaves it.
  function stepDay(delta) {
    var d = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate() + delta, 12)
    root.viewYear = d.getFullYear()
    root.viewMonth = d.getMonth()
    root.selectDay(d.getFullYear(), d.getMonth(), d.getDate())
  }

  // "WEDNESDAY · TODAY", "THURSDAY · TOMORROW", "FRIDAY · NOV 13".
  readonly property string dayHeading: {
    var t = new Date(today.getFullYear(), today.getMonth(), today.getDate())
    var s = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate())
    var diff = Math.round((s - t) / 86400000)
    var suffix = diff === 0 ? "TODAY"
      : diff === 1 ? "TOMORROW"
      : diff === -1 ? "YESTERDAY"
      : Qt.formatDate(selectedDate, s.getFullYear() === t.getFullYear() ? "MMM d" : "MMM d yyyy").toUpperCase()
    if (diff === 0) return Qt.formatTime(root.now, "HH:mm") + " · TODAY"
    return Qt.formatDate(selectedDate, "dddd").toUpperCase() + " · " + suffix
  }

  // ---- "Now" line, Google-style. On today, events in progress get a red
  //      line across them at the elapsed fraction; when nothing is running,
  //      a marker row sits between past and upcoming events.
  readonly property bool viewingToday: selectedKey === todayKey
  readonly property var agendaRows: {
    var events = root.agendaEvents
    if (!root.viewingToday) return events
    var timed = 0, running = false, insertAt = -1
    for (var i = 0; i < events.length; i++) {
      if (events[i].allDay) continue
      timed++
      if (root.isNow(events[i])) running = true
      if (insertAt === -1 && events[i].start > root.now) insertAt = i
    }
    if (timed === 0 || running) return events
    if (insertAt === -1) insertAt = events.length
    var rows = events.slice(0)
    rows.splice(insertAt, 0, { marker: true, title: "", timeLabel: "", location: "", meet: "", link: "", declined: false, tentative: false, allDay: true })
    return rows
  }

  // Only one now-line, like Google: when meetings overlap it goes on the
  // one that started most recently.
  readonly property int nowLineIndex: {
    if (!root.viewingToday) return -1
    var rows = root.agendaRows, best = -1
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].marker || !root.isNow(rows[i])) continue
      if (best === -1 || rows[i].start >= rows[best].start) best = i
    }
    return best
  }

  function progressOf(ev) {
    if (!root.isNow(ev)) return -1
    return Math.max(0, Math.min(1, (root.now - ev.start) / (ev.end - ev.start)))
  }

  function dateForKey(key) {
    var p = String(key).split("-")
    return new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10))
  }

  function loadAgenda(force) {
    var key = root.selectedKey
    if (!force && root.eventsByDay[key] !== undefined) return
    if (agendaProc.running) {
      root.pendingKey = key
      return
    }
    var start = root.dateForKey(key)
    var end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 1)
    root.loadingKey = key
    agendaProc.requestKey = key
    agendaProc.command = ["gws", "calendar", "events", "list", "--params", JSON.stringify({
      calendarId: "primary",
      timeMin: start.toISOString(),
      timeMax: end.toISOString(),
      singleEvents: true,
      orderBy: "startTime",
      maxResults: 50
    })]
    agendaProc.running = true
  }

  function storeAgenda(key, events, error) {
    var next = {}
    for (var k in root.eventsByDay) next[k] = root.eventsByDay[k]
    var errs = {}
    for (var e in root.agendaErrors) errs[e] = root.agendaErrors[e]
    if (error) {
      errs[key] = error
    } else {
      next[key] = events
      delete errs[key]
    }
    root.eventsByDay = next
    root.agendaErrors = errs
  }

  function hhmm(date) {
    return Qt.formatTime(date, "HH:mm")
  }

  function parseEvents(raw) {
    var data = JSON.parse(raw)
    var items = data.items || []
    var out = []
    for (var i = 0; i < items.length; i++) {
      var ev = items[i]
      if (ev.status === "cancelled") continue
      var allDay = !(ev.start && ev.start.dateTime)
      var response = ""
      var attendees = ev.attendees || []
      for (var a = 0; a < attendees.length; a++)
        if (attendees[a].self) response = attendees[a].responseStatus || ""
      var start = allDay ? null : new Date(ev.start.dateTime)
      var end = allDay ? null : new Date(ev.end.dateTime)
      out.push({
        title: ev.summary || "(No title)",
        allDay: allDay,
        start: start,
        end: end,
        timeLabel: allDay ? "All day" : hhmm(start) + " – " + hhmm(end),
        location: ev.location || "",
        meet: ev.hangoutLink || "",
        link: ev.htmlLink || "",
        declined: response === "declined",
        tentative: response === "tentative" || response === "needsAction"
      })
    }
    // All-day events first, then by start time (API order is already by start).
    out.sort(function(x, y) {
      if (x.allDay !== y.allDay) return x.allDay ? -1 : 1
      if (x.allDay) return 0
      return x.start - y.start
    })
    return out
  }

  function isNow(ev) {
    return !ev.allDay && ev.start <= root.now && root.now < ev.end
  }

  function isPast(ev) {
    return !ev.allDay && ev.end <= root.now
  }

  Process {
    id: agendaProc
    property string requestKey: ""
    stdout: StdioCollector {
      id: agendaOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: agendaErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var key = agendaProc.requestKey
      var raw = String(agendaOut.text || "").trim()
      try {
        if (exitCode !== 0 || raw === "") throw new Error("exit " + exitCode)
        root.storeAgenda(key, root.parseEvents(raw), "")
        root.authFailed = false
      } catch (e) {
        root.authFailed = root.looksLikeAuthError(String(agendaErr.text || "") + "\n" + raw)
        var lines = String(agendaErr.text || "").split("\n").filter(function(l) {
          return l.trim() !== "" && l.indexOf("keyring backend") === -1
        })
        root.storeAgenda(key, null, lines.length ? lines[lines.length - 1] : "Could not load events (gws " + e.message + ")")
      }
      if (root.loadingKey === key) root.loadingKey = ""
      if (root.pendingKey !== "") {
        root.pendingKey = ""
        Qt.callLater(function() { root.loadAgenda(false) })
      }
    }
  }

  Timer {
    // Keeps the "now" highlight current while the popup is open.
    interval: 60 * 1000
    repeat: true
    running: root.opened
    onTriggered: root.now = new Date()
  }

  Timer {
    // While disconnected and open, retry often so a finished reconnect
    // shows up on its own without pressing reload.
    interval: 10 * 1000
    repeat: true
    running: root.authFailed && root.opened
    onTriggered: root.loadAgenda(true)
  }

  Timer {
    // Background auto-refresh every 5 minutes, open or not, so the popup
    // shows up-to-date events instantly instead of loading on open.
    interval: 5 * 60 * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.now = new Date()
      // Drop other cached days so they reload when visited; keep the shown one.
      var keep = {}
      if (root.eventsByDay[root.selectedKey] !== undefined) keep[root.selectedKey] = root.eventsByDay[root.selectedKey]
      root.eventsByDay = keep
      root.loadAgenda(true)
    }
  }

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.now = new Date()
    // Show cached events immediately (kept fresh by the 5-minute timer),
    // and quietly re-check today in the background.
    root.goToToday()
    root.loadAgenda(true)
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    root.selectedDate = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 12)
    root.loadAgenda(false)
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(mainRow.implicitWidth + panel.verticalContentInset + Style.space(8))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "," || t === "h") root.stepDay(-1)
        else if (t === "." || t === "l") root.stepDay(1)
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: mainRow.implicitWidth
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Row {
        id: mainRow
        spacing: Style.space(20)

        Column {
          id: calendarColumn
          width: gridColumn.width
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(12)

              Text {
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 30
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 34
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Commons.Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Commons.Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      id: dayCell
                      required property var modelData
                      readonly property bool selected: modelData.key === root.selectedKey

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined; the day shown in the agenda is filled.
                      color: dayCell.selected
                        ? Style.selectedFillFor(root.contentForeground, Commons.Color.accent)
                        : (dayMouse.containsMouse ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent) : "transparent")
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Commons.Color.accent)

                      MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectDay(dayCell.modelData.year, dayCell.modelData.month, dayCell.modelData.day)
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: modelData.day
                        color: modelData.inMonth
                          ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }
        }

        // ---- Divider between month grid and day agenda.
        Rectangle {
          width: Style.spacing.hairline
          height: calendarColumn.height
          color: root.contentForeground
          opacity: 0.1
        }

        // ---- Day agenda, Google Calendar style.
        Item {
          id: agendaPane
          width: root.agendaWidth
          height: calendarColumn.height

          Item {
            id: agendaHeader
            width: parent.width
            height: Math.max(dayLabel.implicitHeight, prevDayButton.height) + Style.space(4)

            // ‹        08:29 · TODAY ⟳        ›
            PanelActionButton {
              id: prevDayButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅁"
              tooltipText: "Previous day"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.stepDay(-1)
            }

            Row {
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                id: dayLabel
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: root.dayHeading
                color: dayLabelMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Commons.Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 18
                font.letterSpacing: 1
                font.bold: true

                MouseArea {
                  id: dayLabelMouse
                  anchors.fill: parent
                  enabled: root.selectedKey !== root.todayKey
                  hoverEnabled: enabled
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.goToToday()

                  PanelToolTip {
                    visible: dayLabelMouse.containsMouse
                    text: "Back to today"
                    fontFamily: root.contentFontFamily
                  }
                }
              }

              PanelActionButton {
                id: reloadButton
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.agendaLoading ? "󰔟" : "󰑐"
                tooltipText: "Reload events"
                foreground: Qt.darker(root.contentForeground, 1.6)
                fontFamily: root.contentFontFamily
                onClicked: root.loadAgenda(true)
              }
            }

            PanelActionButton {
              id: nextDayButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅂"
              tooltipText: "Next day"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.stepDay(1)
            }
          }

          Rectangle {
            id: agendaRule
            anchors.top: agendaHeader.bottom
            anchors.topMargin: Style.space(10)
            width: parent.width
            height: Style.spacing.hairline
            color: root.contentForeground
            opacity: 0.1
          }

          // Status line: loading / error / empty.
          Text {
            anchors.top: agendaRule.bottom
            anchors.topMargin: Style.space(14)
            width: parent.width
            visible: root.agendaEvents.length === 0 && !root.authFailed
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.agendaError !== "" ? root.agendaError
              : (root.agendaLoading || !root.agendaLoaded ? "Loading events…" : "Nothing scheduled")
            color: root.agendaError !== "" ? Commons.Color.urgent : Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---- Disconnected: gws auth failed.
          Column {
            anchors.top: agendaRule.bottom
            anchors.topMargin: Style.space(18)
            width: parent.width
            visible: root.authFailed
            spacing: Style.space(10)

            Row {
              spacing: Style.space(10)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰃮"
                color: Commons.Color.urgent
                font.family: root.contentFontFamily
                font.pixelSize: 22
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "Google Calendar disconnected"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "The gws login has expired or was revoked. Reconnect to load your events again — a browser window opens for the Google sign-in."
              color: Qt.darker(root.contentForeground, 1.3)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              width: reconnectLabel.implicitWidth + Style.space(28)
              height: reconnectLabel.implicitHeight + Style.space(14)
              radius: Style.cornerRadius
              color: reconnectMouse.containsMouse
                ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                : Style.normalFillFor(root.contentForeground, Commons.Color.accent)
              border.width: Style.spacing.hairline
              border.color: reconnectMouse.containsMouse
                ? Style.hoverBorderFor(root.contentForeground, Commons.Color.accent)
                : Style.normalBorderFor(root.contentForeground, Commons.Color.accent)

              Text {
                id: reconnectLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰌘  Reconnect Google"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: reconnectMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.reconnect()
              }
            }

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: "Or in a terminal:  gws auth login"
              color: Qt.darker(root.contentForeground, 1.7)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              width: parent.width
              visible: root.agendaError !== ""
              wrapMode: Text.Wrap
              maximumLineCount: 3
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: root.agendaError
              color: Qt.darker(root.contentForeground, 1.9)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Flickable {
            id: agendaScroll
            visible: !root.authFailed
            anchors.top: agendaRule.bottom
            anchors.topMargin: Style.space(8)
            anchors.bottom: parent.bottom
            width: parent.width
            contentHeight: agendaList.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
              id: agendaList
              width: agendaScroll.width
              spacing: Style.space(4)

              Repeater {
                model: root.agendaRows

                Rectangle {
                  id: eventRow
                  required property var modelData
                  required property int index
                  readonly property bool isMarker: modelData.marker === true
                  readonly property bool current: !isMarker && root.isNow(modelData)
                  readonly property bool past: !isMarker && root.isPast(modelData)
                  readonly property real progress: isMarker || index !== root.nowLineIndex ? -1 : root.progressOf(modelData)

                  width: agendaList.width
                  height: isMarker ? Style.space(10) : eventText.implicitHeight + Style.space(12)
                  radius: Style.cornerRadius
                  color: isMarker ? "transparent" : eventMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                    : (eventRow.current ? Style.selectedFillFor(root.contentForeground, Commons.Color.accent) : "transparent")
                  opacity: modelData.declined ? 0.45 : (eventRow.past ? 0.6 : 1)

                  // Colour bar, like Google's event chips.
                  Rectangle {
                    visible: !eventRow.isMarker
                    x: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(3)
                    height: parent.height - Style.space(10)
                    radius: width / 2
                    color: eventRow.modelData.tentative || eventRow.modelData.declined
                      ? "transparent"
                      : Style.selectedStateColor(root.contentForeground, Commons.Color.accent)
                    border.width: eventRow.modelData.tentative || eventRow.modelData.declined ? Style.spacing.hairline : 0
                    border.color: Style.selectedStateColor(root.contentForeground, Commons.Color.accent)
                  }

                  MouseArea {
                    id: eventMouse
                    anchors.fill: parent
                    enabled: !eventRow.isMarker
                    hoverEnabled: true
                    cursorShape: eventRow.modelData.link !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                      if (eventRow.modelData.link === "") return
                      Qt.openUrlExternally(eventRow.modelData.link)
                      root.close()
                    }
                  }

                  Column {
                    id: eventText
                    visible: !eventRow.isMarker
                    x: Style.space(14)
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - (meetButton.visible ? meetButton.width + Style.space(4) : Style.space(8))
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: eventRow.modelData.title
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      font.bold: eventRow.current
                      font.strikeout: eventRow.modelData.declined
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: eventRow.modelData.timeLabel
                        + (eventRow.modelData.location !== "" ? "  ·  " + eventRow.modelData.location : "")
                      color: Qt.darker(root.contentForeground, 1.5)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  PanelActionButton {
                    id: meetButton
                    visible: !eventRow.isMarker && eventRow.modelData.meet !== "" && !eventRow.past
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰕧"
                    tooltipText: "Join Google Meet"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: {
                      Qt.openUrlExternally(eventRow.modelData.meet)
                      root.close()
                    }
                  }

                  // Red "now" line: across a running event at its elapsed
                  // fraction, or as its own marker row between events.
                  Item {
                    visible: eventRow.isMarker || eventRow.progress >= 0
                    width: parent.width
                    height: Style.space(8)
                    y: eventRow.isMarker
                      ? (parent.height - height) / 2
                      : Math.round(parent.height * Math.max(0, eventRow.progress) - height / 2)
                    z: 10

                    Rectangle {
                      x: Style.space(1)
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(8)
                      height: width
                      radius: width / 2
                      color: Commons.Color.urgent
                    }

                    Rectangle {
                      x: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - x
                      height: Math.max(2, Style.space(2))
                      color: Commons.Color.urgent
                    }
                  }
                }
              }
            }
          }
        }
        }
      }
    }
  }
}
