//! Shared bounded output: a blocked UI must not freeze the Bluetooth reactor.
use crate::Event;
use std::io::{self, Write};
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

pub fn emit(output: &mut impl Write, event: &Event) -> io::Result<()> {
    serde_json::to_writer(&mut *output, event)?;
    output.write_all(b"\n")?;
    output.flush()
}
pub struct EventOutput {
    sender: mpsc::Sender<(Event, oneshot::Sender<io::Result<()>>)>,
    timeout: Duration,
}
impl EventOutput {
    pub fn new(mut writer: impl Write + Send + 'static, timeout: Duration) -> io::Result<Self> {
        let (sender, mut receiver) = mpsc::channel::<(Event, oneshot::Sender<io::Result<()>>)>(4);
        std::thread::Builder::new()
            .name("battery-output".into())
            .spawn(move || {
                while let Some((event, response)) = receiver.blocking_recv() {
                    let result = emit(&mut writer, &event);
                    let failed = result.is_err();
                    let _ = response.send(result);
                    if failed {
                        break;
                    }
                }
            })?;
        Ok(Self { sender, timeout })
    }
    pub async fn emit(&self, event: &Event) -> io::Result<()> {
        let (response, result) = oneshot::channel();
        self.sender
            .try_send((event.clone(), response))
            .map_err(|error| {
                io::Error::other(format!("battery output queue unavailable: {error}"))
            })?;
        tokio::time::timeout(self.timeout, result)
            .await
            .map_err(|_| {
                io::Error::new(io::ErrorKind::TimedOut, "battery output consumer stalled")
            })?
            .map_err(|_| {
                io::Error::new(io::ErrorKind::BrokenPipe, "battery output worker stopped")
            })?
    }
}
pub fn output_closed(fd: std::os::fd::RawFd) -> bool {
    let mut descriptor = libc::pollfd {
        fd,
        events: 0,
        revents: 0,
    };
    // SAFETY: one initialized pollfd, valid for this nonblocking call.
    unsafe {
        libc::poll(&mut descriptor, 1, 0) > 0
            && descriptor.revents & (libc::POLLERR | libc::POLLHUP | libc::POLLNVAL) != 0
    }
}
