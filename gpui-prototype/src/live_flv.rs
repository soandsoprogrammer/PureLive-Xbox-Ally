use std::{
    io::{self, Read, Seek, SeekFrom},
    sync::mpsc::{self, Receiver},
    thread,
};

const REWIND_LIMIT: usize = 2 * 1024 * 1024;
/// Read-ahead window. Bilibili's 原画 runs at 6-10 Mbit/s, so a burst of ~0.8 s
/// of data is enough to ride out CDN jitter without delaying the live edge much.
const CHUNK: usize = 32 * 1024;
const CHUNKS: usize = 24;

pub struct LiveFlv {
    chunks: Receiver<io::Result<Vec<u8>>>,
    current: Vec<u8>,
    offset: usize,
    prefix: Vec<u8>,
    read_position: u64,
    position: u64,
}

impl LiveFlv {
    pub fn open(source: &crate::hardware_player::Input) -> crate::Result<Self> {
        let response = source.request(&source.agent()?, &source.url).call()?;
        let mut body = response.into_body().into_reader();
        let (sender, chunks) = mpsc::sync_channel(CHUNKS);
        // Keeping the HTTP body read ahead of the decoder means a slow packet
        // no longer stalls the picture: it drains from this queue instead.
        thread::spawn(move || {
            loop {
                let mut chunk = vec![0u8; CHUNK];
                match body.read(&mut chunk) {
                    Ok(0) => break,
                    Ok(count) => {
                        chunk.truncate(count);
                        if sender.send(Ok(chunk)).is_err() {
                            break;
                        }
                    }
                    Err(error) => {
                        let _ = sender.send(Err(error));
                        break;
                    }
                }
            }
        });
        Ok(Self {
            chunks,
            current: Vec::new(),
            offset: 0,
            prefix: Vec::new(),
            read_position: 0,
            position: 0,
        })
    }

    fn next_chunk(&mut self) -> io::Result<()> {
        match self.chunks.recv() {
            Ok(Ok(chunk)) => {
                self.current = chunk;
                self.offset = 0;
                Ok(())
            }
            Ok(Err(error)) => {
                self.current.clear();
                self.offset = 0;
                Err(error)
            }
            // The reader thread finished: treat it as EOF.
            Err(_) => {
                self.current.clear();
                self.offset = 0;
                Ok(())
            }
        }
    }
}

impl Read for LiveFlv {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        if buf.is_empty() {
            return Ok(0);
        }
        if self.position < self.read_position {
            let start = self.position as usize;
            let end = (start + buf.len()).min(self.prefix.len());
            let count = end.saturating_sub(start);
            if count > 0 {
                buf[..count].copy_from_slice(&self.prefix[start..end]);
                self.position += count as u64;
                return Ok(count);
            }
            self.position = self.read_position;
        }
        if self.offset >= self.current.len() {
            self.next_chunk()?;
            if self.current.is_empty() {
                return Ok(0);
            }
        }
        let available = &self.current[self.offset..];
        let count = buf.len().min(available.len());
        buf[..count].copy_from_slice(&available[..count]);
        self.offset += count;
        let cached = count.min(REWIND_LIMIT.saturating_sub(self.prefix.len()));
        if cached > 0 {
            self.prefix.extend_from_slice(&buf[..cached]);
        }
        self.read_position += count as u64;
        self.position += count as u64;
        Ok(count)
    }
}

impl Seek for LiveFlv {
    fn seek(&mut self, from: SeekFrom) -> io::Result<u64> {
        let target = match from {
            SeekFrom::Start(target) => Some(target),
            SeekFrom::Current(offset) => self.position.checked_add_signed(offset),
            SeekFrom::End(_) => return Err(io::ErrorKind::Unsupported.into()),
        }
        .ok_or(io::ErrorKind::InvalidInput)?;
        if target < self.read_position && self.read_position > self.prefix.len() as u64 {
            return Err(io::ErrorKind::Unsupported.into());
        }
        if target <= self.read_position {
            self.position = target;
        } else {
            let distance = target - self.position;
            if io::copy(&mut self.take(distance), &mut io::sink())? != distance {
                return Err(io::ErrorKind::UnexpectedEof.into());
            }
        }
        Ok(self.position)
    }
}
