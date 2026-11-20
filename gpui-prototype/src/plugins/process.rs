use std::{
    io::{self, Read, Write},
    os::windows::process::CommandExt,
    path::Path,
    process::{Child, Command, Stdio},
    time::{Duration, Instant},
};

use serde::{Serialize, de::DeserializeOwned};

pub(super) struct PluginProcess(Child);

impl PluginProcess {
    pub(super) fn start(executable: &Path, request: &impl Serialize) -> io::Result<Self> {
        Self::start_with(executable, request, |_| {})
    }

    pub(super) fn start_with(
        executable: &Path,
        request: &impl Serialize,
        configure: impl FnOnce(&mut Command),
    ) -> io::Result<Self> {
        let mut command = Command::new(executable);
        crate::compat::configure_network(&mut command);
        configure(&mut command);
        let mut child = Self(
            command
                .creation_flags(0x08000000)
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()?,
        );
        let input = child.0.stdin.as_mut().expect("piped plugin stdin");
        serde_json::to_writer(&mut *input, request)?;
        input.write_all(b"\n")?;
        Ok(child)
    }

    pub(super) fn close_input(&mut self) {
        self.0.stdin.take();
    }

    pub(super) fn poll<T: DeserializeOwned>(&mut self) -> io::Result<Option<T>> {
        let Some(status) = self.0.try_wait()? else {
            return Ok(None);
        };
        if !status.success() {
            return Err(io::Error::other(format!("plugin exited: {status}")));
        }
        let mut response = Vec::new();
        self.0.stdout.take().expect("piped plugin stdout").take(4097).read_to_end(&mut response)?;
        if response.len() > 4096 {
            return Err(io::Error::other("plugin response exceeds 4096 bytes"));
        }
        Ok(Some(serde_json::from_slice(&response)?))
    }

    pub(super) fn wait<T: DeserializeOwned>(&mut self, timeout: Duration) -> io::Result<T> {
        let deadline = Instant::now() + timeout;
        loop {
            if let Some(response) = self.poll()? {
                return Ok(response);
            }
            if Instant::now() >= deadline {
                return Err(io::Error::new(io::ErrorKind::TimedOut, "plugin response timed out"));
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }
}

impl Drop for PluginProcess {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}
