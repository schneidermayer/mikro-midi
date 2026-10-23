.PHONY: app check check-app run

app:
	./scripts/build-macos.sh

check:
	cargo fmt --all -- --check
	cargo test --workspace --locked
	$(MAKE) check-app

check-app:
	mkdir -p target/swift-checks
	swiftc -parse-as-library macos/MikroAppBehavior.swift scripts/check-app-behavior.swift -o target/swift-checks/app-behavior
	target/swift-checks/app-behavior

run: app
	open "dist/Mikro MIDI.app"
