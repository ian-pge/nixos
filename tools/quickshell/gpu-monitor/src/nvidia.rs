use crate::{Backend, Metrics};
use anyhow::{Context, Result};
use nvml_wrapper::{Nvml, enum_wrappers::device::TemperatureSensor, error::NvmlError};
use std::ffi::OsStr;

// NixOS exposes the userspace library matching the running NVIDIA driver here.
// No LD_LIBRARY_PATH wrapper, vendored driver or nvidia-smi process is needed.
const LIBRARY: &str = "/run/opengl-driver/lib/libnvidia-ml.so.1";

#[derive(Default)]
pub struct Nvidia {
    nvml: Option<Nvml>,
    name: Option<(String, String)>,
}

fn optional<T>(result: Result<T, NvmlError>) -> Result<Option<T>, NvmlError> {
    match result {
        Ok(value) => Ok(Some(value)),
        Err(NvmlError::NotSupported | NvmlError::FunctionNotFound | NvmlError::NoPermission) => {
            Ok(None)
        }
        Err(error) => Err(error),
    }
}

impl Nvidia {
    fn query(&mut self, address: &str) -> Result<Metrics> {
        if self.nvml.is_none() {
            // Sampler has already checked runtime_status. Use normal lazy init:
            // NO_ATTACH makes even an active GPU inaccessible on driver 610.57.04.
            self.nvml = Some(
                Nvml::builder()
                    .lib_path(OsStr::new(LIBRARY))
                    .init()
                    .context("Initializing NVIDIA management library")?,
            );
        }
        let device = self
            .nvml
            .as_ref()
            .unwrap()
            .device_by_pci_bus_id(address)
            .context("Accessing the selected PCI GPU")?;
        if self
            .name
            .as_ref()
            .is_none_or(|(cached, _)| cached != address)
        {
            self.name = optional(device.name())?.map(|name| (address.to_owned(), name));
        }
        let usage = optional(device.utilization_rates())?
            .map(|rates| rates.gpu)
            .filter(|n| *n <= 100);
        let temperature =
            optional(device.temperature(TemperatureSensor::Gpu))?.filter(|n| *n <= 150);
        let memory = optional(device.memory_info())?
            .filter(|memory| memory.total > 0 && memory.used <= memory.total);
        Ok(Metrics {
            name: self.name.as_ref().map(|(_, name)| name.clone()),
            usage,
            temperature_c: temperature,
            memory_used_bytes: memory.as_ref().map(|m| m.used),
            memory_total_bytes: memory.as_ref().map(|m| m.total),
        })
    }
}

impl Backend for Nvidia {
    fn processes(&mut self, address: &str, since: u64) -> Result<serde_json::Value> {
        let nvml = self.nvml.as_ref().context("GPU is not initialized")?;
        let device = nvml.device_by_pci_bus_id(address)?;
        crate::processes::read(&device, since)
    }

    fn read(&mut self, address: &str) -> Result<Metrics> {
        let result = self.query(address);
        if result.is_err() {
            // A lost device or unloaded driver must be reinitialized on retry.
            self.nvml = None;
            self.name = None;
        }
        result
    }

    fn reset(&mut self) {
        self.nvml = None;
        self.name = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn optional_fields_do_not_hide_driver_failures() {
        assert_eq!(optional(Ok(0)).unwrap(), Some(0));
        for error in [
            NvmlError::NotSupported,
            NvmlError::NoPermission,
            NvmlError::FunctionNotFound,
        ] {
            assert_eq!(optional::<u32>(Err(error)).unwrap(), None);
        }
        for error in [
            NvmlError::GpuLost,
            NvmlError::DriverNotLoaded,
            NvmlError::Uninitialized,
        ] {
            assert!(optional::<u32>(Err(error)).is_err());
        }
    }
}
