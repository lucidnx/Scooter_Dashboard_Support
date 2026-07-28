import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15
import QtQuick.Layouts 1.15
import Vedder.vesc.commands 1.0
import Vedder.vesc.utility 1.0

Item {
    id: root
    anchors.fill: parent

    property Commands mCommands: VescIf.commands()
    property int loadedModel: -1
    property bool isSlave: modelBox.currentIndex === 2
    // Load is only complete once every settings message has arrived. Saving
    // before that would write empty fields as 0 and wipe modes/general, so
    // Save stays disabled and the UI keeps re-requesting until all are in.
    property var settingsSeen: ({})
    property int settingsSeenCount: 0
    property bool settingsLoaded: false
    property bool saving: false
    property bool statePending: false
    property double statePendingSince: 0
    readonly property var settingsMsgs: ["model", "general", "temps", "modes",
        "secret", "apply", "gesture", "misc", "rear", "cruise", "alarm"]

    function markSettingsSeen(key) {
        if (settingsMsgs.indexOf(key) < 0 || settingsSeen[key])
            return
        settingsSeen[key] = true
        settingsSeenCount += 1
        if (settingsSeenCount >= settingsMsgs.length)
            settingsLoaded = true
    }

    function resetSettingsLoad() {
        settingsSeen = ({})
        settingsSeenCount = 0
        settingsLoaded = false
    }
    property real titleSize: Qt.application.font.pointSize > 0 ? Qt.application.font.pointSize + 3 : 14

    // Live scooter state for the Control tab
    property bool stOff: false
    property bool stLock: false
    property bool stLight: false
    property bool stSecret: false
    property int stMode: 4
    property real stBatt: 0
    property real stVin: 0
    property real stSpeed: 0
    property real stWatts: 0
    property real stWhkm: 0
    property real stRange: 0
    property real stAmps: 0
    property real stMax: 60
    property bool stCruise: false
    property bool stCruiseEn: false

    function applyStateLine(line) {
        var p = line.split(" ")
        stOff = parseBoolToken(p[1])
        stLock = parseBoolToken(p[2])
        stLight = parseBoolToken(p[3])
        stSecret = parseBoolToken(p[4])
        stMode = Number.parseInt(p[5]) || 4
        stBatt = Number.parseFloat(p[6]) || 0
        stVin = Number.parseFloat(p[7]) || 0
        stSpeed = Number.parseFloat(p[8]) || 0
        stWatts = Number.parseFloat(p[9]) || 0
        stWhkm = Number.parseFloat(p[10]) || 0
        stRange = Number.parseFloat(p[11]) || 0
        stAmps = Number.parseFloat(p[12]) || 0
        stMax = Number.parseFloat(p[13]) || 60
        stCruise = parseBoolToken(p[14])
        stCruiseEn = parseBoolToken(p[15])
    }

    function ctrlCode(str) {
        sendCode(str)
        sendCode("(send-state)")
    }

    function sendCode(str) {
        mCommands.sendCustomAppData(str + "\0")
    }

    // Saving fires many commands - pace them so the BLE link and the
    // script's event queue keep up (a raw burst drops packets over nRF)
    property var sendQueue: []

    Timer {
        id: sendTimer
        interval: 60
        repeat: true
        onTriggered: {
            if (root.sendQueue.length === 0) {
                sendTimer.stop()
                return
            }
            mCommands.sendCustomAppData(root.sendQueue.shift() + "\0")
        }
    }

    function queueCode(str) {
        root.sendQueue.push(str)
        sendTimer.start()
    }

    function boolAtom(box) {
        return box.checked ? "true" : "false"
    }

    function parseBoolToken(token) {
        return token === "true" || token === "1"
    }

    // Wh/km: "0" when zero, one decimal below 10, no decimals from 10 up
    function fmtWhkm(v) {
        if (v < 0.05)
            return "0"
        if (v >= 10)
            return Math.round(v).toString()
        return v.toFixed(1)
    }

    // Lever combo codes: 0=brake+throttle, 1=brake only, 2=throttle only, 3=none
    function comboFromBoxes(brakeBox, throttleBox) {
        if (brakeBox.checked && throttleBox.checked) return 0
        if (brakeBox.checked) return 1
        if (throttleBox.checked) return 2
        return 3
    }

    function setBoxesFromCombo(combo, brakeBox, throttleBox) {
        brakeBox.checked = (combo === 0 || combo === 1)
        throttleBox.checked = (combo === 0 || combo === 2)
    }

    // Boot mode dropdown index <-> speed mode value (2=eco, 1=drive, 4=sport)
    function bootModeValue() {
        return [2, 1, 4][bootMode.currentIndex]
    }

    function setBootMode(value) {
        bootMode.currentIndex = value === 2 ? 0 : (value === 1 ? 1 : 2)
    }

    function pressesIndex(box, token, fallback) {
        var n = Number.parseInt(token)
        box.currentIndex = Number.isNaN(n) ? fallback : n
    }

    function readReal(field, decimals) {
        var number = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(number)) {
            number = 0
        }
        return number.toFixed(decimals)
    }

    function setReal(field, value, decimals) {
        var number = Number(value)
        if (Number.isFinite(number)) {
            field.text = (number % 1 === 0) ? number.toString() : number.toFixed(decimals)
        }
    }

    // Current is shown as a percentage in the UI but stored/sent as a 0-1
    // scale (VESC's l_current_max_scale). Convert at the UI boundary, and
    // HARD-CAP at 100% - this is a multiplier of Motor Current Max, so a value
    // above 100 would over-drive the motor. Never let the save path exceed 1.0.
    function readPct(field) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n)) n = 0
        if (n < 0) n = 0
        if (n > 100) n = 100
        return (n / 100).toFixed(3)
    }

    function setPct(field, value) {
        var n = Number(value) * 100
        if (!Number.isFinite(n)) n = 0
        if (n < 0) n = 0
        if (n > 100) n = 100
        field.text = (Math.abs(n - Math.round(n)) < 0.05) ? Math.round(n).toString() : n.toFixed(1)
    }

    // Clamp a current field to 0-100 as soon as the user leaves it (feedback)
    function clampPct(field) {
        setPct(field, readPct(field))
    }

    // Overmodulation: VESC's floor is 1.0 (no overmod). Never save below 1.0 -
    // an empty field or a mistaken 0 would be an invalid/harmful factor.
    function setOm(field, value) {
        var n = Number(value)
        if (Number.isFinite(n)) field.text = (n < 1.0 ? 1.0 : n).toFixed(3)
    }

    function readOm(field) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n) || n < 1.0) n = 1.0
        return n.toFixed(3)
    }

    function clampOm(field) {
        setOm(field, readOm(field))
    }

    // Light compensation gain: never let a blank/garbage entry through as 0
    // (would divide by zero at runtime); floor/ceiling match the firmware clamp.
    function readGain(field) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n)) n = 1.0
        if (n < 0.3) n = 0.3
        if (n > 3.0) n = 3.0
        return n.toFixed(3)
    }

    function setGain(field, value) {
        var n = Number(value)
        if (!Number.isFinite(n)) n = 1.0
        if (n < 0.3) n = 0.3
        if (n > 3.0) n = 3.0
        field.text = n.toFixed(3)
    }

    function clampGain(field) {
        setGain(field, readGain(field))
    }

    function readOffsetV(field) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n)) n = 0.0
        if (n < -1.5) n = -1.5
        if (n > 1.5) n = 1.5
        return n.toFixed(3)
    }

    function setOffsetV(field, value) {
        var n = Number(value)
        if (!Number.isFinite(n)) n = 0.0
        if (n < -1.5) n = -1.5
        if (n > 1.5) n = 1.5
        field.text = n.toFixed(3)
    }

    function clampOffsetV(field) {
        setOffsetV(field, readOffsetV(field))
    }

    // Calibration wizard state (light compensation sampling). One guided
    // button per channel walks through two held lever positions (released,
    // then full press). At each position the light is toggled off/on/off/on
    // and sampled each time, so the light-off and light-on readings are a
    // paired measurement from the identical lever position.
    property string calibRunning: "" // "" / "thr" / "brk" - which channel is active
    property string calibStage: "idle" // "idle" / "prep" / "settle" / "measure" / "release"
    property string calibPhaseLabel: "rel" // "rel" / "full" - lever position being sampled
    property string calibProgress: "" // "n/total" samples taken, shown while measuring
    readonly property real calibPrepDuration: 3.0 // must match scooter_support.lisp calib-prep-duration
    readonly property real calibReleaseDuration: 3.0 // must match calib-release-duration
    property real calibRemaining: 0
    property string calibStatusThr: "Not calibrated"
    property string calibStatusBrk: "Not calibrated"

    // Shown on the button itself while that channel is running, replacing
    // "Calibrate Throttle/Brake"; falls back to the button's normal label
    function calibButtonText(ch) {
        if (calibRunning !== ch)
            return ch === "thr" ? "Calibrate Throttle" : "Calibrate Brake"
        var subject = ch === "thr" ? "throttle" : "brake"
        if (calibStage === "release") return "Release " + subject + ", ending."
        // the light toggles several times per position, each far too short for
        // a useful countdown - show sample progress across the run instead
        if (calibStage === "settle" || calibStage === "measure")
            return "Measuring... " + calibProgress
        // prep
        var base = (calibPhaseLabel === "full")
            ? "Press " + subject + " to maximum"
            : "Keep " + subject + " released"
        return base + " " + calibRemaining.toFixed(1) + "s"
    }

    function calibStartChannel(ch) {
        if (calibRunning !== "") return
        calibRunning = ch
        calibStage = "prep"
        calibPhaseLabel = "rel"
        calibRemaining = calibPrepDuration
        sendCode(ch === "thr" ? "(calib-start-thr)" : "(calib-start-brk)")
    }

    // Speed fields are stored/sent in km/h but shown in mph when "Use Miles" is
    // on. Convert only at the UI boundary; km/h stays the internal unit.
    readonly property real mphFactor: 0.621371

    function readSpeed(field, decimals) {
        var n = Number.parseFloat(field.text.replace(",", "."))
        if (!Number.isFinite(n)) n = 0
        if (useMph.checked) n = n / mphFactor // mph -> km/h
        return n.toFixed(decimals)
    }

    function setSpeed(field, kmh, decimals) {
        var n = Number(kmh)
        if (!Number.isFinite(n)) return
        if (useMph.checked) n = n * mphFactor // km/h -> mph
        field.text = (Math.abs(n - Math.round(n)) < 0.05) ? Math.round(n).toString() : n.toFixed(decimals)
    }

    // Re-render all speed fields when the unit toggle flips (user action)
    function convertSpeedFields(toMiles) {
        var factor = toMiles ? mphFactor : (1 / mphFactor)
        var fs = [ecoSpeed, driveSpeed, sportSpeed, secretEcoSpeed, secretDriveSpeed,
            secretSportSpeed, minSpeed, buttonSpeed, cruiseDeviation, cruiseMinSpeed,
            cruiseMaxSpeed, alarmSpeedThreshold]
        for (var i = 0; i < fs.length; i++) {
            var n = Number.parseFloat(fs[i].text.replace(",", "."))
            if (Number.isFinite(n)) {
                var v = n * factor
                fs[i].text = (Math.abs(v - Math.round(v)) < 0.05) ? Math.round(v).toString() : v.toFixed(1)
            }
        }
    }

    function saveAllSettings() {
        if (!settingsLoaded || saving)
            return
        saving = true
        saveTimeout.restart()
        queueCode("(save-general-settings "
            + boolAtom(softwareAdc)
            + " " + boolAtom(softwareAdc2)
            + " " + boolAtom(showBatteryInIdle)
            + " " + boolAtom(showBatterySecret)
            + " " + readSpeed(minSpeed, 1)
            + " " + boolAtom(appEnable)
            + ")")

        queueCode("(save-temp-settings "
            + readReal(tempWarningMotor, 1)
            + " " + readReal(tempWarningFet, 1)
            + ")")

        queueCode("(save-mode-settings "
            + readSpeed(ecoSpeed, 1)
            + " " + readPct(ecoCurrent)
            + " " + readReal(ecoWatts, 0)
            + " " + readReal(ecoFw, 1)
            + " " + readSpeed(driveSpeed, 1)
            + " " + readPct(driveCurrent)
            + " " + readReal(driveWatts, 0)
            + " " + readReal(driveFw, 1)
            + " " + readSpeed(sportSpeed, 1)
            + " " + readPct(sportCurrent)
            + " " + readReal(sportWatts, 0)
            + " " + readReal(sportFw, 1)
            + " " + bootModeValue()
            + " " + readOm(ecoOm)
            + " " + readOm(driveOm)
            + " " + readOm(sportOm)
            + ")")

        queueCode("(save-secret-settings "
            + boolAtom(secretEnabled)
            + " " + readSpeed(secretEcoSpeed, 1)
            + " " + readPct(secretEcoCurrent)
            + " " + readReal(secretEcoWatts, 0)
            + " " + readReal(secretEcoFw, 1)
            + " " + readSpeed(secretDriveSpeed, 1)
            + " " + readPct(secretDriveCurrent)
            + " " + readReal(secretDriveWatts, 0)
            + " " + readReal(secretDriveFw, 1)
            + " " + readSpeed(secretSportSpeed, 1)
            + " " + readPct(secretSportCurrent)
            + " " + readReal(secretSportWatts, 0)
            + " " + readReal(secretSportFw, 1)
            + " " + readOm(secretEcoOm)
            + " " + readOm(secretDriveOm)
            + " " + readOm(secretSportOm)
            + ")")

        queueCode("(save-apply-settings "
            + boolAtom(applySpeed)
            + " " + boolAtom(applyCurrent)
            + " " + boolAtom(applyWatts)
            + " " + boolAtom(applyFw)
            + " " + boolAtom(applyOm)
            + " " + boolAtom(secretApplySpeed)
            + " " + boolAtom(secretApplyCurrent)
            + " " + boolAtom(secretApplyWatts)
            + " " + boolAtom(secretApplyFw)
            + " " + boolAtom(secretApplyOm)
            + ")")

        queueCode("(save-gesture-settings "
            + secretPresses.currentIndex
            + " " + comboFromBoxes(secretBrake, secretThrottle)
            + " " + boolAtom(secretRequiresLock)
            + " " + (lockPresses.currentIndex + 1)
            + " " + comboFromBoxes(lockBrake, lockThrottle)
            + " " + modePresses.currentIndex
            + " " + comboFromBoxes(modeBrake, modeThrottle)
            + " " + boolAtom(modeLocked)
            + " " + lightPresses.currentIndex
            + " " + comboFromBoxes(lightBrake, lightThrottle)
            + " " + boolAtom(lightLocked)
            + ")")

        queueCode("(save-misc-settings "
            + boolAtom(lightOnBoot)
            + " " + readSpeed(buttonSpeed, 1)
            + " " + boolAtom(useMph)
            + " " + boolAtom(bmsSoc)
            + " " + boolAtom(secretExitOnLock)
            + " " + (Number.parseInt(appPin.text) || 0)
            + " " + dashPowerOut.currentIndex
            + ")")

        queueCode("(save-light-offsets "
            + readOffsetV(lightOffThr)
            + " " + readGain(lightGainThr)
            + " " + readOffsetV(lightOffBrk)
            + " " + readGain(lightGainBrk)
            + ")")

        queueCode("(save-rear-settings "
            + boolAtom(rearLightEnable)
            + " " + boolAtom(autoTaillight)
            + " " + [1, 2, 0][brakeLightMode.currentIndex]
            + ")")

        queueCode("(save-cruise-settings "
            + boolAtom(cruiseEnable)
            + " " + readReal(cruiseDelay, 1)
            + " " + readSpeed(cruiseDeviation, 1)
            + " " + readSpeed(cruiseMinSpeed, 1)
            + " " + readSpeed(cruiseMaxSpeed, 1)
            + ")")

        queueCode("(save-alarm-settings "
            + boolAtom(alarmTone)
            + " " + readSpeed(alarmSpeedThreshold, 1)
            + " " + readReal(alarmGyroThreshold, 1)
            + " " + readReal(alarmVoltage, 1)
            + ")")

        queueCode("(finish-settings-save)")

        // Model change needs a lisp restart, ack-gated via "model-ok"
        if (modelBox.currentIndex !== loadedModel) {
            queueCode("(save-model " + modelBox.currentIndex + ")")
        }
    }

    function getSettings() {
        sendCode("(send-settings)")
    }

    function applySettingsLine(line) {
        var parts = line.split(" ")
        markSettingsSeen(parts[0])

        if (parts[0] === "model") {
            loadedModel = Number.parseInt(parts[1])
            modelBox.currentIndex = loadedModel
        } else if (parts[0] === "general") {
            softwareAdc.checked = parseBoolToken(parts[1])
            softwareAdc2.checked = parseBoolToken(parts[2])
            showBatteryInIdle.checked = parseBoolToken(parts[3])
            showBatterySecret.checked = parseBoolToken(parts[4])
            setSpeed(minSpeed, parts[5], 1)
            appEnable.checked = parseBoolToken(parts[6])
        } else if (parts[0] === "temps") {
            setReal(tempWarningMotor, parts[1], 1)
            setReal(tempWarningFet, parts[2], 1)
        } else if (parts[0] === "modes") {
            setSpeed(ecoSpeed, parts[1], 1)
            setPct(ecoCurrent, parts[2])
            setReal(ecoWatts, parts[3], 0)
            setReal(ecoFw, parts[4], 1)
            setSpeed(driveSpeed, parts[5], 1)
            setPct(driveCurrent, parts[6])
            setReal(driveWatts, parts[7], 0)
            setReal(driveFw, parts[8], 1)
            setSpeed(sportSpeed, parts[9], 1)
            setPct(sportCurrent, parts[10])
            setReal(sportWatts, parts[11], 0)
            setReal(sportFw, parts[12], 1)
            setBootMode(Number.parseInt(parts[13]) || 4)
            setOm(ecoOm, parts[14])
            setOm(driveOm, parts[15])
            setOm(sportOm, parts[16])
        } else if (parts[0] === "secret") {
            secretEnabled.checked = parseBoolToken(parts[1])
            setSpeed(secretEcoSpeed, parts[2], 1)
            setPct(secretEcoCurrent, parts[3])
            setReal(secretEcoWatts, parts[4], 0)
            setReal(secretEcoFw, parts[5], 1)
            setSpeed(secretDriveSpeed, parts[6], 1)
            setPct(secretDriveCurrent, parts[7])
            setReal(secretDriveWatts, parts[8], 0)
            setReal(secretDriveFw, parts[9], 1)
            setSpeed(secretSportSpeed, parts[10], 1)
            setPct(secretSportCurrent, parts[11])
            setReal(secretSportWatts, parts[12], 0)
            setReal(secretSportFw, parts[13], 1)
            setOm(secretEcoOm, parts[14])
            setOm(secretDriveOm, parts[15])
            setOm(secretSportOm, parts[16])
        } else if (parts[0] === "apply") {
            applySpeed.checked = parseBoolToken(parts[1])
            applyCurrent.checked = parseBoolToken(parts[2])
            applyWatts.checked = parseBoolToken(parts[3])
            applyFw.checked = parseBoolToken(parts[4])
            applyOm.checked = parseBoolToken(parts[5])
            secretApplySpeed.checked = parseBoolToken(parts[6])
            secretApplyCurrent.checked = parseBoolToken(parts[7])
            secretApplyWatts.checked = parseBoolToken(parts[8])
            secretApplyFw.checked = parseBoolToken(parts[9])
            secretApplyOm.checked = parseBoolToken(parts[10])
        } else if (parts[0] === "gesture") {
            pressesIndex(secretPresses, parts[1], 2)
            setBoxesFromCombo(Number.parseInt(parts[2]) || 0, secretBrake, secretThrottle)
            secretRequiresLock.checked = parseBoolToken(parts[3])
            var lp = Number.parseInt(parts[4])
            lockPresses.currentIndex = (Number.isNaN(lp) || lp < 1) ? 1 : lp - 1
            setBoxesFromCombo(Number.parseInt(parts[5]) || 0, lockBrake, lockThrottle)
            pressesIndex(modePresses, parts[6], 2)
            setBoxesFromCombo(Number.parseInt(parts[7]) || 0, modeBrake, modeThrottle)
            modeLocked.checked = parseBoolToken(parts[8])
            pressesIndex(lightPresses, parts[9], 1)
            setBoxesFromCombo(Number.parseInt(parts[10]) || 0, lightBrake, lightThrottle)
            lightLocked.checked = parseBoolToken(parts[11])
        } else if (parts[0] === "misc") {
            useMph.checked = parseBoolToken(parts[3]) // set unit before any speed field
            lightOnBoot.checked = parseBoolToken(parts[1])
            setSpeed(buttonSpeed, parts[2], 1)
            bmsSoc.checked = parseBoolToken(parts[4])
            secretExitOnLock.checked = parseBoolToken(parts[5])
            setOffsetV(lightOffThr, parts[6])
            setGain(lightGainThr, parts[7])
            setOffsetV(lightOffBrk, parts[8])
            setGain(lightGainBrk, parts[9])
            appPin.text = ("00000" + (Number.parseInt(parts[10]) || 0)).slice(-6)
            dashPowerOut.currentIndex = Number.parseInt(parts[11]) || 0
        } else if (parts[0] === "rear") {
            rearLightEnable.checked = parseBoolToken(parts[1])
            autoTaillight.checked = parseBoolToken(parts[2])
            var blm = Number.parseInt(parts[3])
            brakeLightMode.currentIndex = blm === 1 ? 0 : (blm === 2 ? 1 : 2)
        } else if (parts[0] === "cruise") {
            cruiseEnable.checked = parseBoolToken(parts[1])
            setReal(cruiseDelay, parts[2], 1)
            setSpeed(cruiseDeviation, parts[3], 1)
            setSpeed(cruiseMinSpeed, parts[4], 1)
            setSpeed(cruiseMaxSpeed, parts[5], 1)
        } else if (parts[0] === "alarm") {
            alarmTone.checked = parseBoolToken(parts[1])
            setSpeed(alarmSpeedThreshold, parts[2], 1)
            setReal(alarmGyroThreshold, parts[3], 1)
            setReal(alarmVoltage, parts[4], 1)
        }
    }

    Component.onCompleted: {
        getSettings()
    }

    Timer {
        id: restartTimer
        interval: 400
        onTriggered: {
            mCommands.lispSetRunning(true)
            reloadTimer.start()
        }
    }

    Timer {
        id: reloadTimer
        interval: 1500
        onTriggered: getSettings()
    }

    // Client-side countdown for the light-calibration hold. Purely visual -
    // the actual result comes from calib-progress/calib-result messages, so a
    // slightly early/late display here has no functional effect.
    Timer {
        interval: 200
        repeat: true
        running: root.calibRunning !== ""
        onTriggered: {
            root.calibRemaining = Math.max(0, root.calibRemaining - 0.2)
        }
    }

    // Clears the "Saving..." state if the ack never comes back
    Timer {
        id: saveTimeout
        interval: 6000
        onTriggered: root.saving = false
    }

    Dialog {
        id: resetDialog
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 360)
        modal: true
        title: "Reset all settings?"
        standardButtons: Dialog.Yes | Dialog.No
        onAccepted: { resetSettingsLoad(); sendCode("(restore-settings-ui)") }

        Label {
            width: resetDialog.availableWidth
            wrapMode: Text.WordWrap
            text: "This restores every setting to defaults. Your model selection is kept. This cannot be undone."
        }
    }

    // The script may still be booting (or writing first-install defaults)
    // when the UI opens - keep asking until it answers
    Timer {
        interval: 1200
        repeat: true
        running: !root.settingsLoaded
        onTriggered: getSettings()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        TabBar {
            id: tabBar
            Layout.fillWidth: true
            implicitWidth: 0
            clip: true

            property int buttons: 4
            property int buttonWidth: 80

            TabButton {
                text: "Control"
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: "General"
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: "Modes"
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
            TabButton {
                text: "Setup"
                width: Math.max(tabBar.buttonWidth, tabBar.width / tabBar.buttons)
            }
        }

        SwipeView {
            id: swipeView
            currentIndex: tabBar.currentIndex
            interactive: false
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Page {
                enabled: !isSlave

                // Adaptive polling: keep at most one request in flight so it
                // paces to the BLE round-trip instead of piling up (which caused
                // periodic stalls). Re-sends after 700 ms if a reply is lost.
                Timer {
                    interval: 40
                    repeat: true
                    running: swipeView.currentIndex === 0 && !root.isSlave
                    onTriggered: {
                        var now = Date.now()
                        if (!root.statePending || (now - root.statePendingSince) > 700) {
                            root.statePending = true
                            root.statePendingSince = now
                            sendCode("(send-state)")
                        }
                    }
                }

                ScrollView {
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 6

                        Item {
                            Layout.fillWidth: true
                            Layout.topMargin: 48
                            Layout.preferredHeight: speedNum.height

                            Label {
                                id: speedNum
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(useMph.checked ? (root.stSpeed * 0.621371) : root.stSpeed)
                                font.pointSize: root.titleSize * 3.8
                                font.bold: true
                            }
                            Label {
                                id: unitLabel
                                anchors.left: speedNum.right
                                anchors.leftMargin: 10
                                anchors.baseline: speedNum.baseline
                                text: useMph.checked ? "mph" : "km/h"
                                opacity: 0.7
                            }
                            Label {
                                anchors.left: unitLabel.left
                                anchors.bottom: unitLabel.top
                                anchors.bottomMargin: 4
                                visible: root.stCruise
                                text: "CC"
                                font.bold: true
                                color: "#ff7a1a"
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 20
                            spacing: 3
                            Repeater {
                                model: 24
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 10
                                    height: 10
                                    radius: 2
                                    // use the rounded (displayed) speed so the bar fills to the shown number
                                    color: index < Math.min(24, Math.round(Math.round(root.stSpeed) / Math.max(1, root.stMax) * 24)) ? "#ff7a1a" : "#5a5a5a"
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 22
                            spacing: 3
                            Repeater {
                                model: 10
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 20
                                    height: 16
                                    radius: 2
                                    // lit segments shift green -> yellow -> red as charge drops
                                    color: index < Math.round(root.stBatt / 10) ? Qt.hsla((root.stBatt / 100) * 0.333, 0.9, 0.45, 1) : "#5a5a5a"
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Layout.preferredHeight: battPctLabel.height

                            Label {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: fmtWhkm(useMph.checked ? (root.stWhkm / 0.621371) : root.stWhkm)
                                    + (useMph.checked ? " Wh/mi" : " Wh/km")
                                font.pointSize: root.titleSize * 1.15
                                opacity: 0.85
                            }
                            Label {
                                id: battPctLabel
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(root.stBatt) + " %"
                                font.bold: true
                                font.pointSize: root.titleSize * 1.3
                            }
                            Label {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "~" + Math.round(useMph.checked ? (root.stRange * 0.621371) : root.stRange)
                                    + (useMph.checked ? " mi" : " km")
                                font.pointSize: root.titleSize * 1.15
                                opacity: 0.85
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.topMargin: 26
                            horizontalAlignment: Text.AlignHCenter
                            text: root.stVin.toFixed(1) + " V  ·  " + Math.round(root.stWatts) + " W  ·  " + root.stAmps.toFixed(1) + " A"
                            font.pointSize: root.titleSize * 1.15
                            opacity: 0.85
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 18
                            spacing: 12

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 84
                                font.pointSize: root.titleSize
                                font.bold: true
                                text: "POWER"
                                Material.background: root.stOff ? "#3d3d3d" : "#2e7d32"
                                Material.foreground: "#ffffff"
                                onClicked: ctrlCode("(ctrl-power " + (root.stOff ? "true" : "false") + ")")
                            }

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 84
                                font.pointSize: root.titleSize
                                font.bold: true
                                text: root.stLock ? "Unlock" : "Lock"
                                Material.background: root.stLock ? "#c62828" : "#3d3d3d"
                                Material.foreground: "#ffffff"
                                onClicked: ctrlCode("(ctrl-lock " + (root.stLock ? "false" : "true") + ")")
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            spacing: 12

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 84
                                font.pointSize: root.titleSize
                                font.bold: true
                                text: "Light"
                                Material.background: root.stLight ? "#f9a825" : "#3d3d3d"
                                Material.foreground: root.stLight ? "#000000" : "#ffffff"
                                onClicked: ctrlCode("(ctrl-light " + (root.stLight ? "false" : "true") + ")")
                            }

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 84
                                font.pointSize: root.titleSize
                                font.bold: true
                                text: "Secret"
                                Material.background: root.stSecret ? "#6a1b9a" : "#3d3d3d"
                                Material.foreground: "#ffffff"
                                onClicked: ctrlCode("(ctrl-secret " + (root.stSecret ? "false" : "true") + ")")
                            }

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.preferredHeight: 84
                                font.pointSize: root.titleSize
                                font.bold: true
                                // brighter cyan while actively holding, teal when just enabled
                                text: "Cruise"
                                Material.background: root.stCruise ? "#00bcd4" : (root.stCruiseEn ? "#00897b" : "#3d3d3d")
                                Material.foreground: "#ffffff"
                                onClicked: ctrlCode("(ctrl-cruise " + (root.stCruiseEn ? "false" : "true") + ")")
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            spacing: 12

                            Button {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                Layout.preferredWidth: 80
                                font.bold: true
                                text: "Eco"
                                Material.background: root.stMode === 2 ? "#1e88e5" : "#3d3d3d"
                                Material.foreground: "#ffffff"
                                onClicked: ctrlCode("(ctrl-mode 2)")
                            }
                            Button {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                Layout.preferredWidth: 80
                                font.bold: true
                                text: "Drive"
                                Material.background: root.stMode === 1 ? "#43a047" : "#3d3d3d"
                                Material.foreground: "#ffffff"
                                onClicked: ctrlCode("(ctrl-mode 1)")
                            }
                            Button {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                Layout.preferredWidth: 80
                                font.bold: true
                                text: "Sport"
                                Material.background: root.stMode === 4 ? "#e53935" : "#3d3d3d"
                                Material.foreground: "#ffffff"
                                onClicked: ctrlCode("(ctrl-mode 4)")
                            }
                        }

                        Label {
                            Layout.topMargin: 40
                            text: "Lock, unlock and power off only react at standstill."
                            font.pointSize: Qt.application.font.pointSize > 0 ? Qt.application.font.pointSize - 1 : 10
                            opacity: 0.6
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            Page {
                enabled: !isSlave

                ScrollView {
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 4

                        Label { text: "General"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 10 }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Startup Mode"; Layout.fillWidth: true }
                            ComboBox { id: bootMode; Layout.preferredWidth: 100; model: ["Eco", "Drive", "Sport"]; currentIndex: 1 }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Secret"; Layout.fillWidth: true }
                            CheckBox { id: secretEnabled; text: "Enabled"; spacing: 4 }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Disable secret when locked"; Layout.fillWidth: true }
                            CheckBox { id: secretExitOnLock; text: "Enabled"; checked: true; spacing: 4 }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Start Speed (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                            TextField { id: minSpeed; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Auto headlight"; Layout.fillWidth: true }
                            CheckBox { id: lightOnBoot; text: "Enabled"; spacing: 4 }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Always ON Tail light"; Layout.fillWidth: true; enabled: rearLightEnable.checked }
                            CheckBox { id: autoTaillight; text: "Enabled"; spacing: 4; enabled: rearLightEnable.checked }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Brake light"; Layout.fillWidth: true; enabled: rearLightEnable.checked }
                            ComboBox { id: brakeLightMode; Layout.preferredWidth: 100; model: ["On", "Blink", "Off"]; enabled: rearLightEnable.checked }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Battery on idle"; Layout.fillWidth: true }
                            CheckBox { id: showBatteryInIdle; text: "Normal"; spacing: 4 }
                            CheckBox { id: showBatterySecret; text: "Secret"; checked: true; spacing: 4 }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Alarm"; Layout.fillWidth: true }
                            CheckBox { id: alarmTone; text: "Enabled"; spacing: 4 }
                        }

                        Label { text: "Gestures"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 24 }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { text: "Lock"; Layout.preferredWidth: 54 }
                            CheckBox { id: lockBrake; text: "Brake"; checked: true; spacing: 4 }
                            CheckBox { id: lockThrottle; text: "Throttle"; spacing: 4 }
                            Item { Layout.fillWidth: true }
                            ComboBox { id: lockPresses; Layout.preferredWidth: 60; model: ["1", "2", "3", "4", "5"]; currentIndex: 1 }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { text: "Modes"; Layout.preferredWidth: 54 }
                            CheckBox { id: modeBrake; text: "Brake"; spacing: 4 }
                            CheckBox { id: modeThrottle; text: "Throttle"; spacing: 4 }
                            CheckBox { id: modeLocked; text: "Locked"; spacing: 4 }
                            Item { Layout.fillWidth: true }
                            ComboBox { id: modePresses; Layout.preferredWidth: 60; model: ["No", "1", "2", "3", "4", "5"]; currentIndex: 2 }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { text: "Headlight"; Layout.preferredWidth: 54 }
                            CheckBox { id: lightBrake; text: "Brake"; spacing: 4 }
                            CheckBox { id: lightThrottle; text: "Throttle"; spacing: 4 }
                            CheckBox { id: lightLocked; text: "Locked"; spacing: 4 }
                            Item { Layout.fillWidth: true }
                            ComboBox { id: lightPresses; Layout.preferredWidth: 60; model: ["No", "1", "2", "3", "4", "5"]; currentIndex: 1 }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { text: "Secret"; Layout.preferredWidth: 54 }
                            CheckBox { id: secretBrake; text: "Brake"; checked: true; spacing: 4 }
                            CheckBox { id: secretThrottle; text: "Throttle"; checked: true; spacing: 4 }
                            CheckBox { id: secretRequiresLock; text: "Locked"; spacing: 4 }
                            Item { Layout.fillWidth: true }
                            ComboBox { id: secretPresses; Layout.preferredWidth: 60; model: ["No", "1", "2", "3", "4", "5"]; currentIndex: 1 }
                        }
                    }
                }
            }

            Page {
                enabled: !isSlave

                ScrollView {
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 4

                        Label { text: "Normal"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 10 }

                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.preferredWidth: 110 }
                            Label { text: "Eco"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                            Label { text: "Drive"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                            Label { text: "Sport"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox { id: applySpeed; text: "Speed"; checked: true; Layout.preferredWidth: 110 }
                            TextField { id: ecoSpeed; enabled: applySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: driveSpeed; enabled: applySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: sportSpeed; enabled: applySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox { id: applyCurrent; text: "Current %"; checked: true; Layout.preferredWidth: 110 }
                            TextField { id: ecoCurrent; enabled: applyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(ecoCurrent) }
                            TextField { id: driveCurrent; enabled: applyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(driveCurrent) }
                            TextField { id: sportCurrent; enabled: applyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(sportCurrent) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox { id: applyWatts; text: "Watts"; checked: true; Layout.preferredWidth: 110 }
                            TextField { id: ecoWatts; enabled: applyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: driveWatts; enabled: applyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: sportWatts; enabled: applyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox { id: applyFw; text: "Field Weak."; checked: true; Layout.preferredWidth: 110 }
                            TextField { id: ecoFw; enabled: applyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: driveFw; enabled: applyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: sportFw; enabled: applyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox { id: applyOm; text: "Overmod."; Layout.preferredWidth: 110 }
                            TextField { id: ecoOm; enabled: applyOm.checked; text: "1.000"; onEditingFinished: clampOm(ecoOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: driveOm; enabled: applyOm.checked; text: "1.000"; onEditingFinished: clampOm(driveOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: sportOm; enabled: applyOm.checked; text: "1.000"; onEditingFinished: clampOm(sportOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                        }

                        Label { text: "Secret"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 24 }

                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.preferredWidth: 110 }
                            Label { text: "Eco"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                            Label { text: "Drive"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                            Label { text: "Sport"; font.bold: true; Layout.fillWidth: true; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignHCenter }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox { id: secretApplySpeed; text: "Speed"; checked: true; Layout.preferredWidth: 110 }
                            TextField { id: secretEcoSpeed; enabled: secretApplySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: secretDriveSpeed; enabled: secretApplySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: secretSportSpeed; enabled: secretApplySpeed.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox { id: secretApplyCurrent; text: "Current %"; checked: true; Layout.preferredWidth: 110 }
                            TextField { id: secretEcoCurrent; enabled: secretApplyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(secretEcoCurrent) }
                            TextField { id: secretDriveCurrent; enabled: secretApplyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(secretDriveCurrent) }
                            TextField { id: secretSportCurrent; enabled: secretApplyCurrent.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampPct(secretSportCurrent) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox { id: secretApplyWatts; text: "Watts"; checked: true; Layout.preferredWidth: 110 }
                            TextField { id: secretEcoWatts; enabled: secretApplyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: secretDriveWatts; enabled: secretApplyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: secretSportWatts; enabled: secretApplyWatts.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox { id: secretApplyFw; text: "Field Weak."; checked: true; Layout.preferredWidth: 110 }
                            TextField { id: secretEcoFw; enabled: secretApplyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: secretDriveFw; enabled: secretApplyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: secretSportFw; enabled: secretApplyFw.checked; Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CheckBox { id: secretApplyOm; text: "Overmod."; Layout.preferredWidth: 110 }
                            TextField { id: secretEcoOm; enabled: secretApplyOm.checked; text: "1.000"; onEditingFinished: clampOm(secretEcoOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: secretDriveOm; enabled: secretApplyOm.checked; text: "1.000"; onEditingFinished: clampOm(secretDriveOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            TextField { id: secretSportOm; enabled: secretApplyOm.checked; text: "1.000"; onEditingFinished: clampOm(secretSportOm); Layout.fillWidth: true; Layout.preferredWidth: 50; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                        }
                    }
                }
            }

            Page {
                ScrollView {
                    anchors.fill: parent
                    contentWidth: availableWidth
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "Model"; font.bold: true; font.pointSize: root.titleSize; Layout.fillWidth: true }
                            ComboBox {
                                id: modelBox
                                Layout.preferredWidth: 170
                                model: ["G30", "M365/1S/PRO2", "Slave", "G2 (untested)"]
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            enabled: !isSlave

                            Label { text: "Throttle & Brake"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 24 }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Software ADC"; Layout.fillWidth: true }
                                CheckBox { id: softwareAdc; text: "Throttle"; spacing: 4 }
                                CheckBox { id: softwareAdc2; text: "Brake"; spacing: 4 }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: softwareAdc.checked || softwareAdc2.checked

                                Label { text: "Light Compensation"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 24 }

                                Label {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    opacity: 0.7
                                    text: "The headlight sags throttle/brake voltage non-linearly across the lever range. Calibrate walks through 4 steps automatically (get ready, then hold), or edit the values directly."
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    visible: softwareAdc.checked


                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "Throttle Offset (V)"; Layout.fillWidth: true }
                                        TextField { id: lightOffThr; text: "0.000"; Layout.preferredWidth: 90; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampOffsetV(lightOffThr) }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "Throttle Gain (k)"; Layout.fillWidth: true }
                                        TextField { id: lightGainThr; text: "1.000"; Layout.preferredWidth: 90; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampGain(lightGainThr) }
                                    }

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 56
                                        Layout.topMargin: 4
                                        // stays enabled while THIS channel runs (so its own color
                                        // shows, not the greyed-out disabled palette) - only the
                                        // other channel's button locks out; re-tapping is a no-op
                                        enabled: root.calibRunning === "" || root.calibRunning === "thr"
                                        text: root.calibButtonText("thr")
                                        Material.foreground: root.calibRunning === "thr" ? "#d0faff" : "#ffffff"
                                        onClicked: root.calibStartChannel("thr")
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        font.pointSize: Qt.application.font.pointSize > 0 ? Qt.application.font.pointSize - 1 : 10
                                        text: root.calibStatusThr
                                    }

                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    visible: softwareAdc2.checked

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "Brake Offset (V)"; Layout.fillWidth: true }
                                        TextField { id: lightOffBrk; text: "0.000"; Layout.preferredWidth: 90; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampOffsetV(lightOffBrk) }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "Brake Gain (k)"; Layout.fillWidth: true }
                                        TextField { id: lightGainBrk; text: "1.000"; Layout.preferredWidth: 90; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly; onEditingFinished: clampGain(lightGainBrk) }
                                    }

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 56
                                        Layout.topMargin: 4
                                        enabled: root.calibRunning === "" || root.calibRunning === "brk"
                                        text: root.calibButtonText("brk")
                                        Material.foreground: root.calibRunning === "brk" ? "#d0faff" : "#ffffff"
                                        onClicked: root.calibStartChannel("brk")
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        font.pointSize: Qt.application.font.pointSize > 0 ? Qt.application.font.pointSize - 1 : 10
                                        text: root.calibStatusBrk
                                    }
                                }
                            }

                            Label { text: "Gestures"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 24 }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Disable button above (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                TextField { id: buttonSpeed; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            }

                            Label { text: "Temperature"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 24 }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Motor Temp Warning (°C)"; Layout.fillWidth: true }
                                TextField { id: tempWarningMotor; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "FET Temp Warning (°C)"; Layout.fillWidth: true }
                                TextField { id: tempWarningFet; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            }

                            Label { text: "Miscellaneous"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 24 }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Use Miles"; Layout.fillWidth: true }
                                CheckBox {
                                    id: useMph
                                    text: "Enabled"
                                    spacing: 4
                                    // convert already-shown speed fields on user toggle only
                                    onCheckedChanged: if (root.settingsLoaded) root.convertSpeedFields(checked)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Use VESC BMS for dash"; Layout.fillWidth: true }
                                CheckBox { id: bmsSoc; text: "Enabled"; spacing: 4 }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: (root.isSlave ? "App Support"
                                           : (modelBox.currentIndex === 1 ? "Xiaomi" : "Segway")
                                             + " App Support (experimental)")
                                }
                                CheckBox { id: appEnable; text: "Enabled"; spacing: 4 }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "App pairing PIN"; Layout.fillWidth: true }
                                TextField {
                                    id: appPin
                                    enabled: appEnable.checked
                                    Layout.preferredWidth: 100
                                    maximumLength: 6
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Tail Light Output"; Layout.fillWidth: true }
                                CheckBox { id: rearLightEnable; text: "Enabled"; spacing: 4 }
                            }

                            Label {
                                text: "MOSFET on the servo/PPM pin, PWM 200 Hz. Off leaves the pin alone entirely, so it stays free for something else. See the wiring diagram in the README."
                                opacity: 0.6
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Dashboard power Control"; Layout.fillWidth: true }
                                ComboBox { id: dashPowerOut; Layout.preferredWidth: 100; model: ["Off", "ADC1", "ADC2"] }
                            }

                            Label {
                                text: "Switches the dashboard supply from the chosen pin - 3.3V on, 0V off. Needs a step-down whose enable it drives and a 1kOhm pulldown. That pin stops working as a lever input."
                                opacity: 0.6
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Label {
                                visible: dashPowerOut.currentIndex === 1 && !softwareAdc.checked
                                text: "WARNING! You have no throttle!"
                                color: "#ff5252"
                                font.bold: true
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Label {
                                visible: dashPowerOut.currentIndex === 2 && !softwareAdc2.checked
                                text: "WARNING! Cruise control cannot be stopped when braking!"
                                color: "#ff5252"
                                font.bold: true
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Label { text: "Cruise control (experimental)"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 24 }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Cruise Control"; Layout.fillWidth: true }
                                CheckBox { id: cruiseEnable; text: "Enabled"; spacing: 4 }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Activation Delay (s)"; Layout.fillWidth: true }
                                TextField { id: cruiseDelay; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Speed deviation (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                TextField { id: cruiseDeviation; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Min activation speed (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                TextField { id: cruiseMinSpeed; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Max activation speed (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                TextField { id: cruiseMaxSpeed; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            }

                            Label {
                                text: "Cruise activates after holding a steady speed with the throttle for the set delay, then engages when you release the throttle. Any throttle or brake input cancels it instantly. Requires \"Cruise Control\" enabled (not inverted) under App Settings -> ADC -> Buttons, and Software ADC on."
                                opacity: 0.6
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Label { text: "Alarm"; font.bold: true; font.pointSize: root.titleSize; Layout.topMargin: 24 }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Speed Trigger (" + (useMph.checked ? "mph" : "km/h") + ")"; Layout.fillWidth: true }
                                TextField { id: alarmSpeedThreshold; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Gyro Trigger (deg/s)"; Layout.fillWidth: true }
                                TextField { id: alarmGyroThreshold; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label { text: "Volume (V)"; Layout.fillWidth: true }
                                TextField { id: alarmVoltage; Layout.preferredWidth: 100; maximumLength: 7; inputMethodHints: Qt.ImhFormattedNumbersOnly }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: swipeView.currentIndex !== 0

            Button {
                Layout.fillWidth: true
                text: "Reset"
                enabled: !root.saving
                onClicked: resetDialog.open()
            }

            Button {
                Layout.fillWidth: true
                text: "Load"
                onClicked: { resetSettingsLoad(); getSettings() }
            }

            Button {
                Layout.fillWidth: true
                text: root.saving ? "Saving..." : (root.settingsLoaded ? "Save" : "Loading...")
                enabled: root.settingsLoaded && !root.saving
                onClicked: saveAllSettings()
            }
        }
    }

    Connections {
        target: mCommands

        function onCustomAppDataReceived(data) {
            var message = data.toString().trim()

            if (message.startsWith("state ")) {
                root.statePending = false
                applyStateLine(message)
                return
            }

            if (message.startsWith("calib-stage ")) {
                // ["calib-stage", "prep"/"settle"/"measure", phaseLabel] mid-run,
                // the sampling stages also carry [n, total]; or
                // ["calib-stage", "release"/"idle", channel] for the tail end
                var sp = message.split(" ")
                var stage = sp[1]
                if (stage === "prep" || stage === "settle" || stage === "measure") {
                    root.calibStage = stage
                    root.calibPhaseLabel = sp[2]
                    if (stage === "prep") root.calibRemaining = root.calibPrepDuration
                    else root.calibProgress = sp[3] + "/" + sp[4]
                } else if (stage === "release") {
                    root.calibStage = "release"
                    root.calibRemaining = root.calibReleaseDuration
                } else if (stage === "idle") {
                    // release grace period elapsed - real control has resumed
                    root.calibRunning = ""
                    root.calibStage = "idle"
                }
                return
            }
            if (message.startsWith("calib-progress ")) {
                return // covered by the live step instruction; nothing to do
            }
            if (message.startsWith("calib-result ")) {
                // channel stays "running" through the release grace period -
                // cleared later by the "calib-stage idle" message above
                // ["calib-result", "thr"/"brk", offset, gain, offRel, offFull, onRel, onFull]
                var rp = message.split(" ")
                var range = "OFF " + Number(rp[4]).toFixed(2) + "→" + Number(rp[5]).toFixed(2)
                    + "V, ON " + Number(rp[6]).toFixed(2) + "→" + Number(rp[7]).toFixed(2) + "V"
                if (rp[1] === "thr") {
                    setOffsetV(lightOffThr, rp[2])
                    setGain(lightGainThr, rp[3])
                    root.calibStatusThr = "Calibrated (" + range + ") - review the values above, then press Save."
                } else {
                    setOffsetV(lightOffBrk, rp[2])
                    setGain(lightGainBrk, rp[3])
                    root.calibStatusBrk = "Calibrated (" + range + ") - review the values above, then press Save."
                }
                return
            }
            if (message === "calib-refused") {
                var refCh = root.calibRunning
                root.calibRunning = ""
                root.calibStage = "idle"
                var refMsg = "Refused - scooter must be powered on and stationary."
                if (refCh === "brk") root.calibStatusBrk = refMsg
                else root.calibStatusThr = refMsg
                return
            }
            if (message === "calib-aborted") {
                var abortCh = root.calibRunning
                root.calibRunning = ""
                root.calibStage = "idle"
                var abortMsg = "Cancelled - the scooter started moving or was turned off. Try again."
                if (abortCh === "brk") root.calibStatusBrk = abortMsg
                else root.calibStatusThr = abortMsg
                return
            }
            if (message.startsWith("calib-error ")) {
                root.calibRunning = ""
                root.calibStage = "idle"
                var errCh = message.split(" ")[1]
                var errMsg = "Released and full-press readings were too close together. Check the lever actually moved, then try again."
                if (errCh === "thr") root.calibStatusThr = errMsg
                else root.calibStatusBrk = errMsg
                return
            }

            if (message.startsWith("model ")
                    || message.startsWith("general ")
                    || message.startsWith("temps ")
                    || message.startsWith("modes ")
                    || message.startsWith("secret ")
                    || message.startsWith("apply ")
                    || message.startsWith("gesture ")
                    || message.startsWith("misc ")
                    || message.startsWith("rear ")
                    || message.startsWith("cruise ")
                    || message.startsWith("alarm ")) {
                applySettingsLine(message)
            } else if (message === "model-ok") {
                loadedModel = modelBox.currentIndex
                resetSettingsLoad()
                VescIf.emitStatusMessage("Model saved, restarting...", true)
                mCommands.lispSetRunning(false)
                restartTimer.start()
            } else if (message === "ok") {
                root.saving = false
                saveTimeout.stop()
                VescIf.emitStatusMessage("Scooter settings saved.", true)
            }
        }
    }
}
