//! Talking to a running clipd from outside — `clipd clip` in a second
//! terminal, a Stream Deck button. The ring lives in the memory of the
//! process that records, so a request travels through a named pipe to it.
//!
//! The protocol is one line each way: a command (`clip`, `clip 10`,
//! `record`) and an answer that starts with `ok ` or `fehler `.

use anyhow::{Result, bail};
use std::io::{BufRead, BufReader, Read, Write};

/// One pipe per Windows user, so two people signed in at once do not reach
/// each other's clipd.
pub fn pipe_name() -> String {
    let user: String = std::env::var("USERNAME")
        .unwrap_or_default()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
        .collect();
    format!(r"\\.\pipe\clipd-{user}")
}

/// What a request asks for.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Request {
    /// Save the last seconds; `None` means as long as set.
    Clip(Option<u32>),
    /// Start a recording, or end the one running.
    Record,
}

pub fn parse(line: &str) -> Result<Request, String> {
    let mut words = line.split_whitespace();
    match (words.next(), words.next(), words.next()) {
        (Some("clip"), None, None) => Ok(Request::Clip(None)),
        (Some("clip"), Some(secs), None) => match secs.parse::<u32>() {
            Ok(n) if n > 0 => Ok(Request::Clip(Some(n))),
            _ => Err(format!("{secs:?} ist keine Sekundenzahl")),
        },
        (Some("record"), None, None) => Ok(Request::Record),
        _ => Err(format!("Unbekannter Befehl {line:?}")),
    }
}

/// Answers requests on a thread of its own for as long as the process lives.
/// `handler` gets each request and returns the answer text, or why it failed.
#[cfg(windows)]
pub fn serve(handler: impl Fn(Request) -> Result<String, String> + Send + 'static) {
    use std::os::windows::io::FromRawHandle;
    use windows_sys::Win32::Foundation::{CloseHandle, ERROR_PIPE_CONNECTED, GetLastError, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::Storage::FileSystem::{FlushFileBuffers, PIPE_ACCESS_DUPLEX};
    use windows_sys::Win32::System::Pipes::{
        ConnectNamedPipe, CreateNamedPipeW, DisconnectNamedPipe, PIPE_READMODE_BYTE, PIPE_REJECT_REMOTE_CLIENTS,
        PIPE_TYPE_BYTE, PIPE_UNLIMITED_INSTANCES, PIPE_WAIT,
    };

    let name: Vec<u16> = pipe_name().encode_utf16().chain(Some(0)).collect();
    std::thread::Builder::new()
        .name("clipd-control".into())
        .spawn(move || {
            loop {
                // SAFETY: a fresh pipe instance with a NUL-terminated name we own.
                let h = unsafe {
                    CreateNamedPipeW(
                        name.as_ptr(),
                        PIPE_ACCESS_DUPLEX,
                        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                        PIPE_UNLIMITED_INSTANCES,
                        4096,
                        4096,
                        0,
                        std::ptr::null(),
                    )
                };
                if h == INVALID_HANDLE_VALUE {
                    std::thread::sleep(std::time::Duration::from_secs(1));
                    continue;
                }
                // SAFETY: waits for a client on the handle just created.
                let connected = unsafe { ConnectNamedPipe(h, std::ptr::null_mut()) } != 0
                    || unsafe { GetLastError() } == ERROR_PIPE_CONNECTED;
                if !connected {
                    unsafe { CloseHandle(h) };
                    continue;
                }
                // SAFETY: the handle is ours; the File closes it when dropped.
                let file = unsafe { std::fs::File::from_raw_handle(h as _) };
                let mut line = String::new();
                // A short line at most, so a misbehaving client cannot make
                // this buffer without end.
                let _ = BufReader::new((&file).take(256)).read_line(&mut line);
                let answer = match parse(line.trim()).and_then(&handler) {
                    Ok(text) => format!("ok {text}\n"),
                    Err(why) => format!("fehler {}\n", why.replace('\n', " ")),
                };
                let _ = (&file).write_all(answer.as_bytes());
                // SAFETY: the client gets the answer before the pipe goes.
                unsafe {
                    FlushFileBuffers(h);
                    DisconnectNamedPipe(h);
                }
            }
        })
        .expect("Thread für Anfragen von außen");
}

#[cfg(not(windows))]
pub fn serve(_handler: impl Fn(Request) -> Result<String, String> + Send + 'static) {}

/// Sends `command` to the running clipd and returns its answer.
pub fn request(command: &str) -> Result<String> {
    const ERROR_PIPE_BUSY: i32 = 231;
    let mut tries = 0;
    let pipe = loop {
        match std::fs::OpenOptions::new().read(true).write(true).open(pipe_name()) {
            Ok(p) => break p,
            Err(e) if e.raw_os_error() == Some(ERROR_PIPE_BUSY) && tries < 40 => {
                tries += 1;
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                bail!("Es läuft kein clipd, das aufnimmt — erst `clipd run` oder das Fenster starten.")
            }
            Err(e) => bail!("clipd antwortet nicht: {e}"),
        }
    };
    (&pipe).write_all(format!("{command}\n").as_bytes())?;
    let mut answer = String::new();
    BufReader::new(&pipe).read_line(&mut answer)?;
    let answer = answer.trim_end();
    match answer.split_once(' ') {
        Some(("ok", text)) => Ok(text.to_string()),
        Some(("fehler", why)) => bail!("{why}"),
        _ if answer == "ok" => Ok(String::new()),
        _ => bail!("clipd antwortet Unverständliches: {answer:?}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn understands_the_commands() {
        assert_eq!(parse("clip"), Ok(Request::Clip(None)));
        assert_eq!(parse(" clip 10 "), Ok(Request::Clip(Some(10))));
        assert_eq!(parse("record"), Ok(Request::Record));
        for bad in ["", "clip 0", "clip zehn", "clip 1 2", "löschen"] {
            assert!(parse(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn the_pipe_belongs_to_the_user() {
        assert!(pipe_name().starts_with(r"\\.\pipe\clipd-"));
        assert!(!pipe_name()[9..].contains(['\\', ' ']));
    }
}
