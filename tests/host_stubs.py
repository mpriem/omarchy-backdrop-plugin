"""Minimal host interfaces for offline QML binding tests, not compositor emulation."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]


def setup_host(base):
    for file in ROOT.glob('*.qml'):
        shutil.copy2(file, base / file.name)
    for file in ROOT.glob('*.js'):
        shutil.copy2(file, base / file.name)
    for name in ('Panel.qml', 'Background.qml'):
        path = base / name
        path.write_text(path.read_text().replace('import Quickshell.Hyprland', 'import qs.TestHost'))
    files = {
        'TestHost/qmldir': 'singleton Hyprland 1.0 Hyprland.qml\n',
        'TestHost/Hyprland.qml': '''pragma Singleton
import QtQuick
QtObject {
 property var focusedWorkspace: ({id: 11})
 property var focusedMonitor: ({name: "DP", activeWorkspace: {id: 11}})
 property var workspaces: ({values: [{id: 11}]})
 function monitorFor(screen) { return null }
}''',
        'Commons/qmldir': 'singleton Util 1.0 Util.qml\nsingleton Color 1.0 Color.qml\nsingleton Style 1.0 Style.qml\n',
        'Commons/Util.qml': '''pragma Singleton
import QtQuick
QtObject {
 function fileUrl(path) { return "file://" + path }
 function execArgv(argv) {}
 function alpha(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity) }
 function decodeBase64(text) { return Qt.atob(text) }
}''',
        'Commons/Color.qml': '''pragma Singleton
import QtQuick
QtObject { property color foreground: "white"; property int applied: 0
 function loadColors(text) { applied += 1 }
 function loadShell(text) {}
}''',
        'Commons/Style.qml': '''pragma Singleton
import QtQuick
QtObject {
 property var font: ({family: "sans", caption: 11, bodySmall: 11, body: 13, title: 16, display: 20})
 property real cornerRadius: 6
 function space(n) { return n }
 function scheduleRefresh() {}
}''',
        'Ui/PanelHero.qml': '''import QtQuick
Item { property string title; property string meta; property string detail
 property color foreground; property string fontFamily; property Component iconComponent
 implicitHeight: 70
}''',
        'Ui/Panel.qml': '''import QtQuick
Item {
 property string moduleName
 property string ipcTarget
 property var bar: null
 property bool opened: false
 property color barForeground: "white"
 function close() { opened = false }
 function toggle() { opened = !opened }
}''',
        'Ui/KeyboardPanel.qml': '''import QtQuick
Item {
 property var anchorItem; property var owner; property var bar
 property bool open; property var focusTarget
 property real contentWidth; property real contentHeight
 width: contentWidth; height: contentHeight
 function fittedContentWidth(v) { return v }
 function fittedContentHeight(v) { return Math.min(300, v) }
}''',
        'Ui/PanelKeyCatcher.qml': '''import QtQuick
Item { property bool blocked
 signal moveRequested(int dx, int dy)
 signal activateRequested()
 signal closeRequested()
 signal tabRequested(int direction)
}''',
        'Ui/BarIconButton.qml': '''import QtQuick
Item { property var bar; property string text; property string tooltipText
 implicitWidth: 30; implicitHeight: 30; signal pressed(int b)
}''',
        'Ui/Button.qml': '''import QtQuick
Item { property string text; property string iconText; property bool hasCursor
 property color foreground; property string fontFamily; property bool bordered; property bool selected
 implicitWidth: 70; implicitHeight: 30
 signal clicked(); signal hovered(bool h)
}''',
        'Ui/PanelSectionHeader.qml': '''import QtQuick
Text { property color foreground; property string fontFamily }''',
        'Ui/PanelSeparator.qml': '''import QtQuick
Item { property color foreground; implicitHeight: 1 }''',
        'Ui/CursorSurface.qml': '''import QtQuick
Rectangle { property bool outline; property color foreground; property bool hasCursor }''',
        'Ui/PanelSlider.qml': '''import QtQuick
Item { property var bar; property real minimum; property real maximum; property real step
 property bool integer; property real value; implicitHeight: 30
 signal moved(real v); signal released(real v)
}''',
        'Ui/TextField.qml': '''import QtQuick
TextInput { property string placeholderText; property color foreground; property bool hasCursor
 property bool hovered; height: 30
}''',
        'BackgroundScreen.qml': '''import QtQuick
Item { required property var modelData; required property var renderer
 property var screen: modelData
 property string screenName: modelData.name
 property int shownWorkspace: 11
 property string displayedImage: renderer.imageFor(screenName, shownWorkspace)
 property string incomingImage: ""
 property int residentCount: 0
 property var keep: []
 property string loadError: ""
}'''
    }
    for name, source in files.items():
        path = base / name
        path.parent.mkdir(exist_ok=True)
        path.write_text(source)
    state = base / '.local/state/omarchy/current'
    backgrounds = state / 'theme/backgrounds'
    backgrounds.mkdir(parents=True)
    (state / 'theme.name').write_text('test')
    for name in ('a.png', 'b.png', 'c.png'):
        (backgrounds / name).write_bytes(b'synthetic')
    (state / 'background').symlink_to(backgrounds / 'a.png')
    (base / '.config/omarchy').mkdir(parents=True)
