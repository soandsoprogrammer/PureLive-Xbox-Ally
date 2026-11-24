use crate::stream_input::StreamInput;
use std::io::{self, Read, Seek, SeekFrom};

const BLOCK: u64 = 1024 * 1024;

pub(super) struct HttpFile {
    source: StreamInput,
    agent: ureq::Agent,
    size: u64,
    position: u64,
    start: u64,
    bytes: Vec<u8>,
}

impl HttpFile {
    pub(super) fn open(source: StreamInput) -> io::Result<Self> {
        let agent = source.agent();
        let (size, bytes) = fetch(&source, &agent, 0, BLOCK - 1, None)?;
        Ok(Self { source, agent, size, position: 0, start: 0, bytes })
    }
}

fn fetch(
    source: &StreamInput,
    agent: &ureq::Agent,
    start: u64,
    end: u64,
    size: Option<u64>,
) -> io::Result<(u64, Vec<u8>)> {
    let response = source.request(agent, &source.url)
        .header("Range", format!("bytes={start}-{end}"))
        .header("Accept-Encoding", "identity")
        .call().map_err(io::Error::other)?;
    if response.status().as_u16() != 206 {
        return Err(io::Error::other("回放服务器不支持分段读取"));
    }
    let (offsets, total) = response.headers().get("Content-Range")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("bytes "))
        .and_then(|value| value.split_once('/'))
        .ok_or_else(|| io::Error::other("回放服务器返回了无效范围"))?;
    let (first, last) = offsets.split_once('-')
        .ok_or_else(|| io::Error::other("回放服务器返回了无效范围"))?;
    let first = first.parse::<u64>().map_err(io::Error::other)?;
    let last = last.parse::<u64>().map_err(io::Error::other)?;
    let total = total.parse::<u64>().map_err(io::Error::other)?;
    if first != start || last < first || last > end || last >= total
        || size.is_some_and(|size| size != total)
    {
        return Err(io::Error::other("回放服务器返回的范围不匹配"));
    }
    let length = last - first + 1;
    let mut bytes = Vec::with_capacity(length as usize);
    response.into_body().into_reader().take(length + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 != length {
        return Err(io::Error::other("回放数据长度不匹配"));
    }
    Ok((total, bytes))
}

impl Read for HttpFile {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        if out.is_empty() || self.position >= self.size {
            return Ok(0);
        }
        if self.position < self.start || self.position - self.start >= self.bytes.len() as u64 {
            let start = self.position / BLOCK * BLOCK;
            let end = start.saturating_add(BLOCK - 1).min(self.size - 1);
            let (_, bytes) = fetch(&self.source, &self.agent, start, end, Some(self.size))?;
            self.start = start;
            self.bytes = bytes;
            if self.position - self.start >= self.bytes.len() as u64 {
                let (_, bytes) = fetch(&self.source, &self.agent, self.position, end, Some(self.size))?;
                self.start = self.position;
                self.bytes = bytes;
            }
        }
        let offset = (self.position - self.start) as usize;
        let count = out.len().min(self.bytes.len() - offset);
        out[..count].copy_from_slice(&self.bytes[offset..offset + count]);
        self.position += count as u64;
        Ok(count)
    }
}

impl Seek for HttpFile {
    fn seek(&mut self, from: SeekFrom) -> io::Result<u64> {
        let position = match from {
            SeekFrom::Start(offset) => Some(offset),
            SeekFrom::Current(offset) => self.position.checked_add_signed(offset),
            SeekFrom::End(offset) => self.size.checked_add_signed(offset),
        };
        self.position = position.ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "无效回放位置"))?;
        Ok(self.position)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{io::{BufRead, BufReader, Write}, net::TcpListener};

    #[test]
    fn supports_seeking_between_http_ranges() {
        let server = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = server.local_addr().unwrap();
        let worker = std::thread::spawn(move || {
            for (start, end, byte) in [(0, BLOCK - 1, b'a'), (BLOCK, BLOCK + 3, b'z')] {
                let (mut stream, _) = server.accept().unwrap();
                stream.set_read_timeout(Some(std::time::Duration::from_secs(3))).unwrap();
                let mut reader = BufReader::new(&mut stream);
                let mut range = String::new();
                loop {
                    let mut line = String::new();
                    assert!(reader.read_line(&mut line).unwrap() > 0);
                    if line == "\r\n" { break; }
                    if line.to_ascii_lowercase().starts_with("range:") {
                        range = line.split_once(':').unwrap().1.trim().to_owned();
                    }
                }
                assert_eq!(range, format!("bytes={start}-{end}"));
                let length = end - start + 1;
                write!(stream, "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes {start}-{end}/{}\r\nContent-Length: {length}\r\nConnection: close\r\n\r\n", BLOCK + 4).unwrap();
                stream.write_all(&vec![byte; length as usize]).unwrap();
            }
        });
        let mut file = HttpFile::open(StreamInput { url: format!("http://{address}/replay.mp4"), headers: Default::default() }).unwrap();
        let mut buffer = [0; 4];
        file.read_exact(&mut buffer).unwrap();
        assert_eq!(&buffer, b"aaaa");
        assert_eq!(file.seek(SeekFrom::End(-4)).unwrap(), BLOCK);
        file.read_exact(&mut buffer).unwrap();
        assert_eq!(&buffer, b"zzzz");
        assert_eq!(file.read(&mut buffer).unwrap(), 0);
        worker.join().unwrap();
    }
}
