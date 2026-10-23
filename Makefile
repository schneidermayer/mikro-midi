.PHONY: app check run

app:
	./scripts/build-macos.sh

check:
	cargo fmt --all -- --check
	cargo test --workspace --locked

run: app
	open "dist/Mikro MIDI.app"
