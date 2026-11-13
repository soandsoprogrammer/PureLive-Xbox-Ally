use std::io::{self, BufReader, Read, Seek, SeekFrom};

const REWIND_LIMIT: usize = 2 * 1024 * 1024;

pub struct LiveFlv {
    body: BufReader<ureq::BodyReader<'static>>,
    prefix: Vec<u8>,
    read_position: u64,
    position: u64,
}

impl LiveFlv {
    pub fn open(source: &crate::hardware_player::Input) -> crate::Result<Self> {
        let response = source.request(&source.agent()?, &source.url).call()?;
        Ok(Self {
            body: BufReader::new(response.into_body().into_reader()),
            prefix: Vec::new(),
            read_position: 0,
            position: 0,
        })
    }
}

impl Read for LiveFlv {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let count = if self.position < self.read_position {
            (&self.prefix[self.position as usize..]).read(buf)?
        } else {
            let count = self.body.read(buf)?;
            let cached = count.min(REWIND_LIMIT - self.prefix.len());
            self.prefix.extend_from_slice(&buf[..cached]);
            self.read_position += count as u64;
            count
        };
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
