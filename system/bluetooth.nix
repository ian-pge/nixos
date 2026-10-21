{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # AdvertisementMonitor is BlueZ's passive background observation API.
    # KernelExperimental remains disabled.
    settings.General.Experimental = true;
    # Experimental also enables RAP (channel sounding) on generic GATT peers.
    # Keep that previously disabled feature off; passive battery monitoring
    # requires neither ranging nor a GATT connection.
    disabledPlugins = ["rap"];
  };
}
