"""Offscreen tests use temporary homes and never connect to the desktop IPC."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class QmlTests(unittest.TestCase):
    def run_qml(self, body, setup=None):
        with tempfile.TemporaryDirectory(prefix='backgrounds-qml-') as tmp:
            base = Path(tmp)
            for name in ('Config.js', 'ConfigStore.qml', 'BackgroundCatalog.qml', 'catalog.py'):
                shutil.copy2(ROOT / name, base / name)
            runtime = base / 'runtime'
            runtime.mkdir(mode=0o700)
            if setup:
                setup(base)
            (base / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  function check(ok, message) { if (!ok) { console.error("TEST FAILED: " + message); Qt.quit() } }
''' + body + '''
  Timer { interval: 8000; running: true; onTriggered: { console.error("TEST TIMEOUT"); Qt.quit() } }
}
''')
            env = dict(os.environ, HOME=tmp, XDG_RUNTIME_DIR=str(runtime), XDG_CACHE_HOME=str(base / 'cache'),
                       QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_STYLE_OVERRIDE='Basic', QT_QUICK_BACKEND='software', QML_DISABLE_DISK_CACHE='1')
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            env.pop('WAYLAND_DISPLAY', None)
            result = subprocess.run(['quickshell', '-p', str(base / 'shell.qml'), '--no-duplicate'],
                                    env=env, capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertIn('TEST PASSED', output, output)
            for error in ('TEST FAILED', 'TEST TIMEOUT', 'ReferenceError', 'TypeError', 'Binding loop', 'Failed to load configuration'):
                self.assertNotIn(error, output, output)
            return output

    def test_store_serialization_and_read_failure(self):
        self.run_qml('''
  ConfigStore { id: store; path: Quickshell.env("HOME") + "/settings.json"; writable: true }
  FileView { id: external; path: store.path; blockWrites: true }
  Timer {
    interval: 200; running: true
    onTriggered: {
      check(store.valid, "missing initial file is editable")
      check(store.mutate({type: "pin", theme: "t", target: "DP", value: "/one"}) === "ok", "pin persisted")
      check(store.mutate({type: "transition", key: "ms", value: 750}) === "ok", "duration persisted")
      check(store.config.pins.t.DP === "/one", "unrelated edit retained")
      check(store.config.transition.ms === 750, "confirmed config published")
      external.setText("{broken")
      external.waitForJob()
      var result = store.mutate({type: "mode", value: "classic"})
      check(result.indexOf("error:") === 0, "damaged JSON blocks save")
      check(store.config.transition.ms === 750, "last valid config survives")
      external.reload(); external.waitForJob()
      check(external.text() === "{broken", "damaged file not overwritten")
      external.setText('{"mode":"pinned","custom":42}'); external.waitForJob()
      check(store.mutate({type: "rotate", key: "every", value: "45s"}) === "ok", "repair resumes editing")
      check(store.config.mode === "pinned" && store.config.custom === 42, "external edit merged before operation")
      console.log("TEST PASSED store")
      Qt.quit()
    }
  }
''')

    @unittest.skipIf(os.geteuid() == 0, "permission failure requires an unprivileged uid")
    def test_store_save_failure(self):
        def setup(base):
            folder = base / 'readonly'
            folder.mkdir()
            (folder / 'settings.json').write_text('{"mode":"workspace"}')
            folder.chmod(0o500)
        self.run_qml('''
  ConfigStore { id: store; path: Quickshell.env("HOME") + "/readonly/settings.json"; writable: true }
  Timer { interval: 200; running: true; onTriggered: {
    var result = store.mutate({type: "mode", value: "classic"})
    check(result.indexOf("error:") === 0, "save failure returned")
    check(store.config.mode === "workspace", "failed write not published")
    check(!store.saving && store.error !== "", "failure state visible")
    console.log("TEST PASSED failure"); Qt.quit()
  } }
''', setup)

    def test_catalog_qml(self):
        def setup(base):
            folder = base / '.local/state/omarchy/current/theme/backgrounds'
            folder.mkdir(parents=True)
            (folder / 'one.png').touch()
            (folder.parent.parent / 'theme.name').write_text('test')
        self.run_qml('''
  BackgroundCatalog { id: catalog }
  Timer { interval: 100; repeat: true; running: true; onTriggered: {
    if (!catalog.generation) return
    check(catalog.images.length === 1, "completed catalog published")
    check(catalog.themeName === "test", "theme identity published")
    check(catalog.revision(catalog.images[0]) !== "missing", "content revision available")
    console.log("TEST PASSED catalog"); Qt.quit()
  } }
''', setup)

    def test_image_lifetime_and_recovery(self):
        def setup(base):
            import struct, zlib
            def png(path, rgb):
                def chunk(kind, value):
                    return struct.pack('>I', len(value)) + kind + value + struct.pack('>I', zlib.crc32(kind + value))
                path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0' + bytes(rgb) * 2) * 2)) + chunk(b'IEND', b''))
            png(base / 'one.png', [255, 0, 0])
            png(base / 'two.png', [0, 255, 0])
            (base / 'bad.png').write_text('corrupt image')
            for name in ('BackgroundScreen.qml', 'RevealMask.qml'):
                shutil.copy2(ROOT / name, base / name)
            # The compositor window backend is unavailable offscreen. Keep the
            # complete production image/state body in a plain Item inside Window.
            screen = base / 'BackgroundScreen.qml'
            source = screen.read_text().replace('PanelWindow {', 'Item {', 1)
            source = source.replace('  screen: modelData', '  property var screen: modelData')
            source = source.replace('  anchors { top: true; bottom: true; left: true; right: true }', '  width: 640; height: 360')
            source = source.replace('  color: "transparent"\n', '').replace('  updatesEnabled: true\n', '')
            source = '\n'.join(line for line in source.splitlines() if 'WlrLayershell.' not in line and 'exclusionMode:' not in line)
            screen.write_text(source)
            commons = base / 'Commons' 
            commons.mkdir()
            (commons / 'qmldir').write_text('singleton Util 1.0 Util.qml\n')
            (commons / 'Util.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function fileUrl(p) { return "file://" + p } }')
            ui = base / 'Ui'
            ui.mkdir()
            (ui / 'ScreenMoveRemap.qml').write_text('import QtQuick\nItem { property var window; property bool remapping: false }')
        self.run_qml('''
  QtObject {
    id: renderer
    property string home: Quickshell.env("HOME")
    property string previewImage: ""
    property var images: [home + "/one.png", home + "/two.png"]
    property string target: images[0]
    property int catalogGeneration: 1
    property string transitionStyle: "fade"
    property int transitionMs: 300
    property int themeReadyRequest: 0
    property int instantSerial: 0
    property var warm: []
    function imageFor(screen, workspace) { return target }
    function residentFor(screen) { return warm }
    function imageRevision(path) { return String(catalogGeneration) }
    function instantFor(screen, path) { return instantSerial }
    function applyPendingTheme(request) {}
    function openSelector() {}
    function openThemeSwitcher() {}
  }
  Window { visible: true; width: 640; height: 360
    BackgroundScreen { id: screen; modelData: Quickshell.screens[0]; renderer: renderer }
  }
  property int step: 0
  property string oldKey: ""
  Timer { interval: 50; repeat: true; running: true; onTriggered: {
    if (step === 0 && screen.displayedImage === renderer.images[0] && screen.residentCount === 1) {
      check(screen.residentCount === 1, "initial residency")
      oldKey = screen.displayedKey
      renderer.target = renderer.images[1]
      step = 1
    } else if (step === 1 && screen.incomingImage !== "") {
      check(screen.displayedKey === oldKey && screen.residentCount === 2, "outgoing texture retained")
      renderer.transitionStyle = "cut"; renderer.transitionMs = 0
      check(screen.activeStyle === "fade" && screen.activeMs === 300, "transition settings snapshotted")
      step = 2
    } else if (step === 2 && screen.displayedImage === renderer.images[1] && screen.incomingImage === "" && screen.residentCount === 1) {
      check(screen.residentCount === 1, "retired texture removed from residency")
      renderer.target = renderer.home + "/bad.png"
      step = 3
    } else if (step === 3 && screen.loadError !== "" && screen.displayedImage === renderer.images[0] && screen.residentCount === 1) {
      check(screen.residentCount === 1, "corrupt target falls back")
      oldKey = screen.displayedKey
      renderer.catalogGeneration += 1
      step = 4
    } else if (step === 4 && screen.displayedKey !== oldKey && screen.displayedImage === renderer.images[0] && screen.residentCount === 1) {
      check(screen.residentCount === 1, "new revision replaces texture")
      renderer.images = []; renderer.target = renderer.home + "/missing.png"
      step = 5
    } else if (step === 5 && screen.targetImage === "") {
      check(screen.displayedImage === renderer.home + "/one.png", "no valid image retains last good texture")
      check(screen.residentCount === 1, "no residency drift")
      console.log("TEST PASSED images"); Qt.quit()
    }
  } }
''', setup)

    def test_renderer_orchestration(self):
        from host_stubs import setup_host
        self.run_qml('''
  Background { id: renderer }
  Timer { interval: 100; repeat: true; running: true; onTriggered: {
    if (renderer.images.length !== 3) return
    var a = renderer.images[0], b = renderer.images[1], c = renderer.images[2]
    check(renderer.setMode("workspace") === "ok", "workspace mode")
    check(renderer.setWorkspaceAssign("modulo") === "ok", "modulo mode")
    check(renderer.pick(c, false) === "ok", "pick accepted")
    check(renderer.imageFor("DP", 11) === c, "workspace 11 explicit pick")
    check(renderer.setMode("pinned") === "ok", "pinned mode")
    renderer.pick(b, false)
    check(renderer.imageFor("DP", 11) === b, "pinned pick")
    renderer.setMode("rotate")
    for (var order of ["ordered", "random"]) {
      renderer.setRotate("order", order)
      for (var scope of ["same", "different"]) {
        renderer.setRotate("scope", scope)
        renderer.pick(c, false)
        check(renderer.imageFor("DP", 11) === c, "rotation pick " + order + " " + scope)
      }
    }
    renderer.plannedRotate = {generation: -1, state: {base: "/gone", own: {}}}
    renderer.rotateStep()
    check(renderer.images.indexOf(renderer.imageFor("DP", 11)) >= 0, "stale plan ignored")
    renderer.setMode("classic")
    renderer.pick(b, true)
    check(renderer.imageFor("DP", 11) === b && renderer.instantSerial > 0, "instant classic pick")
    renderer.themeRequest = 2; renderer.themePending = true
    renderer.applyPendingTheme(1)
    check(renderer.themePending, "stale completion cannot apply new theme")
    renderer.applyPendingTheme(2)
    check(!renderer.themePending, "matching completion applies theme")
    console.log("TEST PASSED renderer"); Qt.quit()
  } }
''', setup_host)

    def test_panel_navigation_and_overflow(self):
        from host_stubs import setup_host
        def setup(base):
            setup_host(base)
            (base / '.config/omarchy/background.json').write_text('{"mode":"workspace","workspaceAssign":"fixed"}')
        self.run_qml('''
  Window { visible: true; width: 600; height: 400; Panel { id: settings } }
  Timer { interval: 300; running: true; onTriggered: {
    settings.opened = true
    check(settings.editWorkspace === "11", "focused workspace 11 preserved")
    check(settings.homeIndex("target") === 10, "target index from options")
    settings.setCursor("target", 10); settings.activateCursor()
    check(settings.editWorkspace === "11", "workspace 11 activated safely")
    settings.selectedIndex = 999; settings.activateCursor()
    for (var id of ["mode", "assign", "target", "search", "picker", "style", "duration", "try"]) {
      settings.setCursor(id, 0); settings.ensureCursorVisible()
    }
    function findViewport(item) {
      if (item.contentY !== undefined && item.contentHeight > item.height) return item
      for (var child of item.children || []) { var found = findViewport(child); if (found) return found }
      return null
    }
    var viewport = findViewport(settings)
    check(viewport !== null, "tall content has a viewport")
    check(viewport.contentY > 0, "keyboard focus scrolls into view")
    console.log("TEST PASSED panel"); Qt.quit()
  } }
''', setup)


if __name__ == '__main__':
    unittest.main()
