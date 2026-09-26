import QtQuick
import QtMultimedia

// Instantiated on demand, so the microphone is never opened by a hidden panel.
QtObject {
  id: root
  required property string outputPath
  readonly property bool recording: recorder.recorderState === MediaRecorder.RecordingState
  readonly property int duration: recorder.duration
  signal finished(string path)
  signal failed(string message)
  property bool started: false
  property CaptureSession session: CaptureSession {
    audioInput: AudioInput {}
    recorder: MediaRecorder {
      id: recorder
      outputLocation: "file://" + root.outputPath
      mediaFormat.fileFormat: MediaFormat.Ogg
      mediaFormat.audioCodec: MediaFormat.AudioCodec.Opus
      audioChannelCount: 1
      audioBitRate: 64000
      onRecorderStateChanged: {
        if (recorderState === MediaRecorder.RecordingState) root.started = true;
        else if (root.started && recorderState === MediaRecorder.StoppedState && error === MediaRecorder.NoError) root.finished(root.outputPath);
      }
      onErrorOccurred: root.failed(errorString)
    }
  }
  function start() { recorder.record(); }
  function stop() { recorder.stop(); }
}
