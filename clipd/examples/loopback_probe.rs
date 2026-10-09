//! Entwicklungshilfe: prüft, ob WASAPI auf diesem Rechner einen Mitschnitt
//! zulässt, und wo es klemmt. `cargo run --example loopback_probe`
//!
//! Vergleicht bewusst drei Fälle: Mikrofon (normale Aufnahme), Wiedergabegerät
//! als Loopback, und beide Apartment-Modelle.

use std::time::{Duration, Instant};
use wasapi::{Direction, StreamMode};

fn main() {
    for sta in [false, true] {
        for (label, dev_dir) in [("Mikrofon (normal)", Direction::Capture), ("Lautsprecher (Loopback)", Direction::Render)] {
            let name = format!("{label}, {}", if sta { "STA" } else { "MTA" });
            let (tx, rx) = std::sync::mpsc::channel();
            std::thread::spawn(move || {
                let _ = tx.send(try_open(sta, dev_dir));
            });
            match rx.recv_timeout(Duration::from_secs(4)) {
                Ok(Ok(ms)) => println!("{name:32} -> OK nach {ms} ms"),
                Ok(Err(e)) => println!("{name:32} -> Fehler: {e}"),
                Err(_) => println!("{name:32} -> HÄNGT in Initialize"),
            }
        }
    }
}

fn try_open(sta: bool, dev_dir: Direction) -> Result<u128, String> {
    let t = Instant::now();
    let hr = if sta { wasapi::initialize_sta() } else { wasapi::initialize_mta() };
    hr.ok().map_err(|e| format!("COM: {e}"))?;
    let enumerator = wasapi::DeviceEnumerator::new().map_err(|e| format!("Enumerator: {e}"))?;
    let device = enumerator.get_default_device(&dev_dir).map_err(|e| format!("Gerät: {e}"))?;
    let mut client = device.get_iaudioclient().map_err(|e| format!("Client: {e}"))?;
    let mix = client.get_mixformat().map_err(|e| format!("Mixformat: {e}"))?;
    let mode = StreamMode::PollingShared { autoconvert: false, buffer_duration_hns: 0 };
    // Immer als Aufnahme initialisieren; bei einem Wiedergabegerät ist genau
    // das der Loopback.
    client.initialize_client(&mix, &Direction::Capture, &mode).map_err(|e| format!("Initialize: {e}"))?;
    client.start_stream().map_err(|e| format!("Start: {e}"))?;
    Ok(t.elapsed().as_millis())
}
