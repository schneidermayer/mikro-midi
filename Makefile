.PHONY: app check check-app check-launch run

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
	swiftc -parse-as-library macos/MikroLoginItem.swift scripts/check-login-item.swift -o target/swift-checks/login-item
	target/swift-checks/login-item
	swiftc -parse-as-library macos/MikroAppBehavior.swift macos/MikroLoginItem.swift macos/MikroModel.swift scripts/check-background.swift -o target/swift-checks/background
	target/swift-checks/background

check-launch: app
	swift scripts/check-launch.swift "dist/Mikro MIDI.app"

run: app
	open "dist/Mikro MIDI.app"
