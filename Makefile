SHELL := /usr/bin/env bash

.PHONY: all deps branding check iso run run-bios run-sb clean

all: check iso

deps:
	@./scripts/deps.sh

branding:
	@./scripts/build-branding.sh

check:
	@./scripts/check-profile.sh

iso:
	@./scripts/build.sh

run:
	@./scripts/test-qemu.sh --uefi

run-bios:
	@./scripts/test-qemu.sh --bios

run-sb:
	@./scripts/test-qemu.sh --uefi --secureboot

clean:
	@rm -rf work out
	@echo "Removed work/ and out/."
