use std::io::{self, BufRead};

type Tile = [u8; 4];
const GRID: u8 = 12;

// [automatic, horizontal, vertical, main picture]
fn layouts(rooms: usize) -> Option<[Vec<Tile>; 4]> {
    let auto = match rooms {
        2 => vec![[0, 0, 6, 12], [6, 0, 6, 12]],
        3 => vec![[0, 0, 6, 12], [6, 0, 6, 6], [6, 6, 6, 6]],
        4 => vec![[0, 0, 6, 6], [6, 0, 6, 6], [0, 6, 6, 6], [6, 6, 6, 6]],
        _ => return None,
    };
    let rooms = rooms as u8;
    let step = GRID / rooms;
    let horizontal = (0..rooms).map(|index| [index * step, 0, step, GRID]).collect();
    let vertical = (0..rooms).map(|index| [0, index * step, GRID, step]).collect();
    let side = GRID / (rooms - 1);
    let mut main = vec![[0, 0, 8, GRID]];
    main.extend((0..rooms - 1).map(|index| [8, index * side, 4, side]));
    Some([auto, horizontal, vertical, main])
}

#[derive(serde::Deserialize)]
#[serde(untagged)]
enum Request {
    Current { rooms: usize },
    Legacy(usize),
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut input = String::new();
    io::stdin().lock().read_line(&mut input)?;
    let request: Request = serde_json::from_str(&input)?;
    let rooms = match request { Request::Current { rooms } | Request::Legacy(rooms) => rooms };
    let tiles = layouts(rooms).ok_or("expected two to four rooms")?;
    let output = match request {
        Request::Current { .. } => serde_json::to_string(&tiles)?,
        Request::Legacy(_) => serde_json::to_string(&tiles[0].iter().map(|tile| tile.map(|n| n / 6)).collect::<Vec<_>>())?,
    };
    println!("{output}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_layout_fills_the_screen_without_overlap() {
        for count in 2..=4 {
            for tiles in layouts(count).unwrap() {
                let mut cells = [false; 144];
                assert_eq!(tiles.len(), count);
                for [x, y, width, height] in tiles {
                    for row in y..y + height {
                        for col in x..x + width {
                            let cell = &mut cells[usize::from(row * GRID + col)];
                            assert!(!*cell);
                            *cell = true;
                        }
                    }
                }
                assert!(cells.into_iter().all(|cell| cell));
            }
        }
        assert!(layouts(1).is_none());
        assert!(layouts(5).is_none());
    }
}
