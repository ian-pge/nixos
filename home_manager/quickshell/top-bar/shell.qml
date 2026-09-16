import Quickshell

ShellRoot {
  KeyboardCheatsheet {}

  StatusData {
    id: sharedStatus
  }

  Variants {
    model: Quickshell.screens

    Bar {
      statusData: sharedStatus
    }
  }
}
