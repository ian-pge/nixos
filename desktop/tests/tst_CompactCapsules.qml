import QtQuick
import QtTest
import Quickshell

// Pure views with inert controllers: no microphone, player or hardware access.
ShellRoot {
  id: fixture
  property var theme: null
  property var views: []
  property var standaloneWaveform: null
  QtObject {
    id: audio
    property int volume: 65
    readonly property real volumeStep: 0.05
    function icon() { return "volume-2"; }
  }
  QtObject {
    id: brightness
    function value(monitor) { return 80; }
    function icon(monitor) { return "sun"; }
  }
  QtObject {
    id: dictation
    property bool recording: false
    property real energy: 0.5
    property bool speechDetected: true
    property var spectrumLevels: []
  }
  QtObject {
    id: media
    property var player: null
    property bool playing: false
    property string labelText: "Example track"
    readonly property string playbackIconText: playing ? "pause" : "play"
  }
  Window { id: window; visible: true; width: 650; height: 250 }
  function create(path, properties) {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/" + path + ".qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString()); Qt.exit(1); return null;
    }
    return component.createObject(window.contentItem, properties);
  }
  Component.onCompleted: {
    theme = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../ui/Theme.js" as T; QtObject { property var library: T }', fixture).library;
    views = [create("audio/VolumeIndicator", {controller: audio, y: 0}),
      create("brightness/BrightnessIndicator", {controller: brightness, y: 50}),
      create("dictation/VoiceDictationIndicator", {controller: dictation, y: 100}),
      create("audio/NowPlayingIndicator", {controller: media, y: 150})];
    standaloneWaveform = create("dictation/VoiceWaveform", {
      speechDetected: false, accent: "white", active: false, y: 210
    });
  }
  TestResult { id: results }
  TestCase {
    name: "CompactCapsules"
    when: fixture.standaloneWaveform !== null && window.visible
    function cleanupTestCase() {
      console.log("CompactCapsules: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function test_height_and_width_follow_the_bar() {
      for (const view of views) {
        compare(view.implicitHeight, fixture.theme.barGroupHeight);
        compare(view.height, fixture.theme.barGroupHeight);
      }
      compare(views[0].implicitWidth, fixture.theme.barSize(280));
      compare(views[1].implicitWidth, fixture.theme.barSize(280));
      compare(views[2].implicitWidth, fixture.theme.barSize(140));
      compare(views[0].radius, fixture.theme.barSize(18));
    }
    function test_content_grows_with_the_background() {
      const icon = findChild(views[0], "volumeIndicatorIcon");
      compare(icon.size, fixture.theme.barSize(17)); compare(icon.x, fixture.theme.barSize(15));
      compare(findChild(views[0], "volumeIndicatorTrack").height, fixture.theme.barSize(8));
      compare(findChild(views[1], "brightnessIndicatorIcon").size, fixture.theme.barSize(17));
      compare(findChild(views[3], "mediaLabel").font.pixelSize, fixture.theme.barSize(16));
      compare(findChild(views[3], "mediaEqualizer").width, fixture.theme.barSize(18));
      verify(findChild(views[3], "mediaLabel").width > 0);
    }
    function test_only_the_bar_waveform_is_scaled() {
      const waveform = findChild(views[2], "dictationWaveform");
      compare(waveform.height, fixture.theme.barSize(22));
      fuzzyCompare(waveform.barWidth, 2.2 * fixture.theme.barScale, 0.001);
      compare(standaloneWaveform.sizeScale, 1);
      compare(standaloneWaveform.barWidth, 2.2);
      compare(standaloneWaveform.implicitHeight, 22);
      dictation.recording = true;
      wait(50);
      verify(waveform.visible);
      compare(waveform.barCount, 19);
      dictation.recording = false;
    }
    function test_voice_bars_stay_in_place_and_keep_the_same_scale_after_a_peak() {
      const wave = standaloneWaveform;
      wave.active = true; wave.speechDetected = true;
      const levels = Array.from({length: 19}, (_, i) => i === 9 ? 0.5 : 0.1);
      wave.spectrumLevels = levels;
      wait(250);
      const bars = Array.from({length: 19}, (_, i) => findChild(wave, "voiceBar" + i));
      const heights = bars.map(bar => bar.height), positions = bars.map(bar => bar.x);
      verify(heights[9] > heights[0]);
      wait(200);
      bars.forEach((bar, i) => { fuzzyCompare(bar.height, heights[i], 0.001); compare(bar.x, positions[i]); });
      wave.spectrumLevels = Array(19).fill(1); wait(150);
      wave.spectrumLevels = levels; wait(250);
      bars.forEach((bar, i) => fuzzyCompare(bar.height, heights[i], 0.001));
      wave.speechDetected = false; wait(250);
      bars.forEach(bar => fuzzyCompare(bar.height, wave.barWidth, 0.001));
      wave.active = false; wave.spectrumLevels = [];
    }
    function test_media_uses_catppuccin_yellow() {
      const indicator = views[3], icon = findChild(indicator, "mediaPlaybackIcon");
      try {
        for (const playing of [false, true, false]) {
          media.playing = playing;
          compare(icon.name, playing ? "pause" : "play");
          compare(icon.color.toString(), "#eed49f");
          for (let index = 0; index < 4; ++index)
            compare(findChild(indicator, "mediaEqualizerBar" + index).color.toString(), playing ? "#eed49f" : "#6e738d");
        }
      } finally { media.playing = false; }
    }
  }
}
