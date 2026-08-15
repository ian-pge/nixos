import Quickshell

ShellRoot {
  StatusData {
    id: sharedStatus
  }

  Variants {
    model: Quickshell.screens

    Bar {
      statusData: sharedStatus
    }
  }

  Variants {
    model: Quickshell.screens

    OsdOverlay {
      statusData: sharedStatus
    }
  }
}
