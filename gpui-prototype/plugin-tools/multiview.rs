use std::io::{self, BufRead};

type Tile = [u8; 4];

fn layout(rooms: usize) -> Option<&'static [Tile]> {
    match rooms {
        2 => Some(&[[0, 0, 1, 2], [1, 0, 1, 2]]),
        3 => Some(&[[0, 0, 1, 2], [1, 0, 1, 1], [1, 1, 1, 1]]),
        4 => Some(&[[0, 0, 1, 1], [1, 0, 1, 1], [0, 1, 1, 1], [1, 1, 1, 1]]),
        _ => None,
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut input = String::new();
    io::stdin().lock().read_line(&mut input)?;
    let rooms: usize = serde_json::from_str(&input)?;
    let tiles = layout(rooms).ok_or("expected two to four rooms")?;
    println!("{}", serde_json::to_string(tiles)?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_supported_layout_fills_the_screen_without_overlap() {
        for count in 2..=4 {
            let mut cells = [false; 4];
            let tiles = layout(count).unwrap();
            assert_eq!(tiles.len(), count);
            for &[x, y, width, height] in tiles {
                for row in y..y + height {
                    for col in x..x + width {
                        let cell = &mut cells[usize::from(row * 2 + col)];
                        assert!(!*cell);
                        *cell = true;
                    }
                }
            }
            assert!(cells.into_iter().all(|cell| cell));
        }
        assert!(layout(1).is_none());
        assert!(layout(5).is_none());
    }
}
