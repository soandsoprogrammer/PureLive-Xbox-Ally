use std::{
    fs::{self, File, OpenOptions},
    io::{self, BufRead, BufWriter, Read, Write},
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering::Relaxed},
    },
    time::{SystemTime, UNIX_EPOCH},
};

#[path = "../src/hls.rs"]
mod hls;
#[path = "../src/stream_input.rs"]
mod stream_input;

use hls::Hls;
use stream_input::StreamInput;
use url::Url;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

#[derive(serde::Deserialize)]
struct Source {
    #[serde(flatten)]
    input: StreamInput,
    data_dir: PathBuf,
}

fn main() -> Result<()> {
    let mut line = String::new();
    io::stdin().lock().read_line(&mut line)?;
    let source: Source = serde_json::from_str(&line)?;
    let stopped = Arc::new(AtomicBool::new(false));
    let cancel = stopped.clone();
    std::thread::spawn(move || {
        // The host closes stdin on Stop, when switching streams, or when exiting.
        let _ = io::stdin().lock().read_line(&mut String::new());
        cancel.store(true, Relaxed);
    });
    let message = record(&source, || stopped.load(Relaxed)).unwrap_or_else(|error| error.to_string());
    println!("{}", serde_json::to_string(&message)?);
    Ok(())
}

fn record(source: &Source, stopped: impl Fn() -> bool) -> Result<String> {
    let url = Url::parse(&source.input.url).map_err(|_| "当前播放地址不支持录制")?;
    if !matches!(url.scheme(), "http" | "https") {
        return Err("只支持录制 HTTP(S) 直播流".into());
    }

    let directory = std::env::var_os("PURELIVE_RECORDINGS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| source.data_dir.join("recordings"));
    let mut output = Recording { directory, file: None, has_media: false };
    let result = if url.path().to_ascii_lowercase().ends_with(".m3u8") {
        record_hls(&source.input, &mut output, stopped)
    } else {
        (|| -> Result<()> {
            let response = source.input.request(&source.input.agent(), url.as_str()).call()?;
            record_flv(response.into_body().into_reader(), &mut output, stopped)
        })()
    };
    output.finish(result)
}

fn record_flv(mut input: impl Read, output: &mut Recording, stopped: impl Fn() -> bool) -> Result<()> {
    let mut header = vec![0; 9];
    input.read_exact(&mut header)?;
    if !header.starts_with(b"FLV") {
        return Err("当前直播源不是 FLV 或 HLS".into());
    }
    let start = u32::from_be_bytes(header[5..9].try_into()?) as usize;
    if !(9..=64 * 1024).contains(&start) {
        return Err("无效的 FLV 文件头".into());
    }
    header.resize(start + 4, 0);
    input.read_exact(&mut header[9..])?;

    let mut tag = Vec::new();
    while !stopped() {
        let mut tag_header = [0; 11];
        if input.read(&mut tag_header[..1])? == 0 {
            break;
        }
        input.read_exact(&mut tag_header[1..])?;
        let size = u32::from_be_bytes([0, tag_header[1], tag_header[2], tag_header[3]]) as usize;
        tag.resize(11 + size + 4, 0);
        tag[..11].copy_from_slice(&tag_header);
        input.read_exact(&mut tag[11..])?;
        if u32::from_be_bytes(tag[11 + size..].try_into()?) as usize != 11 + size {
            return Err("无效的 FLV 数据块".into());
        }
        output.write("flv", &header, &tag, matches!(tag_header[0] & 0x1f, 8 | 9))?;
    }
    Ok(())
}

fn record_hls(source: &StreamInput, output: &mut Recording, stopped: impl Fn() -> bool) -> Result<()> {
    let mut hls = Hls::open(source)?;
    let mut initial_map: Option<Vec<u8>> = None;
    let mut first = true;
    while let Some(segment) = hls.next_segment(&stopped)? {
        if segment.data.is_empty() {
            continue;
        }
        if first {
            initial_map = segment.init.map(<[u8]>::to_vec);
            first = false;
        } else if initial_map.as_deref() != segment.init {
            return Err("HLS 初始化分段发生变化，已停止当前文件".into());
        }
        let (extension, prefix) = segment.init.map_or(("ts", &[][..]), |init| ("mp4", init));
        output.write(extension, prefix, &segment.data, true)?;
    }
    Ok(())
}

struct Recording {
    directory: PathBuf,
    file: Option<(PathBuf, BufWriter<File>)>,
    has_media: bool,
}

impl Recording {
    fn write(&mut self, extension: &str, prefix: &[u8], data: &[u8], has_media: bool) -> io::Result<()> {
        if self.file.is_none() {
            fs::create_dir_all(&self.directory)?;
            let stamp = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos();
            let path = self.directory.join(format!("live-{}-{stamp}.{extension}", std::process::id()));
            let file = OpenOptions::new().write(true).create_new(true).open(&path)?;
            self.file = Some((path, BufWriter::new(file)));
            self.file.as_mut().expect("opened recording").1.write_all(prefix)?;
        }
        self.file.as_mut().expect("opened recording").1.write_all(data)?;
        self.has_media |= has_media;
        Ok(())
    }

    fn finish(self, result: Result<()>) -> Result<String> {
        let Some((path, mut file)) = self.file else {
            result?;
            return Err("没有收到可保存的直播音视频".into());
        };
        file.flush()?;
        file.get_ref().sync_all()?;
        if !self.has_media {
            drop(file);
            fs::remove_file(path)?;
            result?;
            return Err("没有收到可保存的直播音视频".into());
        }
        Ok(match result {
            Ok(()) => format!("录制已保存：{}", path.display()),
            Err(error) => format!("已保存中断前的录制：{}（{error}）", path.display()),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const HEADER: &[u8] = b"FLV\x01\x01\x00\x00\x00\x09\x00\x00\x00\x00";
    const TAG: &[u8] = b"\x09\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x17\x00\x00\x00\x0c";

    #[test]
    fn saves_complete_flv_tags_when_the_connection_ends_mid_tag() {
        let directory = std::env::temp_dir().join(format!("purelive-test-flv-{}", std::process::id()));
        let input = [HEADER, TAG, &TAG[..13]].concat();
        let mut output = Recording { directory: directory.clone(), file: None, has_media: false };
        let result = record_flv(input.as_slice(), &mut output, || false);
        assert!(result.is_err());
        let path = output.file.as_ref().unwrap().0.clone();
        assert!(output.finish(result).unwrap().starts_with("已保存中断前"));
        assert_eq!(fs::read(path).unwrap(), [HEADER, TAG].concat());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn saves_hls_media_and_writes_mp4_initialization_once() {
        use std::net::TcpListener;

        const PLAYLIST: &str = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:2\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:2.0,\none.m4s\n#EXTINF:2.0,\ntwo.m4s\n#EXT-X-ENDLIST\n";
        let server = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = server.local_addr().unwrap();
        let responses = [
            ("/live.m3u8", PLAYLIST),
            ("/init.mp4", "init"),
            ("/one.m4s", "first"),
            ("/two.m4s", "second"),
        ];
        let thread = std::thread::spawn(move || {
            for (expected, body) in responses {
                let (mut socket, _) = server.accept().unwrap();
                socket.set_read_timeout(Some(std::time::Duration::from_secs(3))).unwrap();
                let mut request = io::BufReader::new(&mut socket);
                let mut line = String::new();
                request.read_line(&mut line).unwrap();
                assert_eq!(line.split_whitespace().nth(1), Some(expected));
                loop {
                    line.clear();
                    assert!(request.read_line(&mut line).unwrap() > 0);
                    if line == "\r\n" {
                        break;
                    }
                }
                write!(socket, "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).unwrap();
            }
        });

        let directory = std::env::temp_dir().join(format!("purelive-test-hls-{}", std::process::id()));
        let mut output = Recording { directory: directory.clone(), file: None, has_media: false };
        let source = StreamInput {
            url: format!("http://{address}/live.m3u8"),
            headers: Default::default(),
        };
        let result = record_hls(&source, &mut output, || false);
        let path = output.file.as_ref().unwrap().0.clone();
        assert_eq!(path.extension().unwrap(), "mp4");
        assert!(output.finish(result).unwrap().starts_with("录制已保存"));
        thread.join().unwrap();
        assert_eq!(fs::read(path).unwrap(), b"initfirstsecond");
        fs::remove_dir_all(directory).unwrap();
    }


    #[test]
    fn rejects_local_files_without_creating_a_recording() {
        let source = Source {
            input: StreamInput { url: "file:///C:/video.mkv".into(), headers: Default::default() },
            data_dir: ".".into(),
        };
        assert_eq!(record(&source, || false).unwrap_err().to_string(), "只支持录制 HTTP(S) 直播流");
    }
}
