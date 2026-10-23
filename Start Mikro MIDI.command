#!/bin/zsh
set -eu
cd -- "${0:A:h}"

if [[ ! -x ./target/release/driver ]]; then
  print 'Build the driver first with: cargo build --release --locked'
  exit 1
fi

print 'Mikro MK3 MIDI bridge'
print 'Select "Mikro MIDI" as the MIDI input in your music app.'
print 'Keep this window open. Press Control-C to stop and release all notes.'
print ''
exec ./target/release/driver --config ./macos_config.toml
