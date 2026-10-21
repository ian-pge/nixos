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

#[cfg(test)]
mod tests {
    use super::*;
    fn event() -> Event {
        Event::Relay {
            mode: "passive",
            available: false,
            phone: None,
            fitbit: None,
            observed_at: None,
            received_at: 1,
        }
    }
    #[test]
    fn idle_output_closure_is_detected_without_a_write() {
        use std::os::{fd::AsRawFd, unix::net::UnixStream};
        let (writer, reader) = UnixStream::pair().unwrap();
        assert!(!output_closed(writer.as_raw_fd()));
        drop(reader);
        assert!(output_closed(writer.as_raw_fd()));
    }
    #[test]
    fn each_event_is_a_complete_json_line() {
        let mut output = Vec::new();
        emit(&mut output, &event()).unwrap();
        assert_eq!(output.last(), Some(&b'\n'));
        let value: serde_json::Value = serde_json::from_slice(&output).unwrap();
        assert_eq!(value["event"], "relay");
        assert_eq!(value["mode"], "passive");
        assert!(value["phone"].is_null());
    }
    #[tokio::test]
    async fn stalled_output_does_not_block_the_radio_reactor() {
        struct Stalled(std::sync::mpsc::Receiver<()>);
        impl Write for Stalled {
            fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
                let _ = self.0.recv();
                Ok(bytes.len())
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let (release, gate) = std::sync::mpsc::channel();
        let output = EventOutput::new(Stalled(gate), Duration::from_millis(20)).unwrap();
        let result = output.emit(&event()).await;
        drop(release);
        assert_eq!(result.unwrap_err().kind(), io::ErrorKind::TimedOut);
    }
    #[test]
    fn closed_consumer_returns_an_error_not_a_panic() {
        struct Closed;
        impl Write for Closed {
            fn write(&mut self, _: &[u8]) -> io::Result<usize> {
                Err(io::ErrorKind::BrokenPipe.into())
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        assert_eq!(
            emit(&mut Closed, &event()).unwrap_err().kind(),
            io::ErrorKind::BrokenPipe
        );
    }
}
