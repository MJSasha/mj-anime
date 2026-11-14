.PHONY: check test native-test build hooks

# Safe default: does not build, sign, install or start a device.
check:
	./tools/check.sh

test:
	"$${FLUTTER_SDK:+$$FLUTTER_SDK/bin/}flutter" test --no-pub

native-test:
	./tools/test_android.sh

build:
	./tools/build.sh

hooks:
	git config --local core.hooksPath .githooks
