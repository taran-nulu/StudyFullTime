SHELL := /bin/bash

BUILD := .build
APP := $(BUILD)/StudyFullTime.app
SDK := $(shell xcrun --show-sdk-path)
TARGET := $(shell uname -m)-apple-macos11.0

CORE_SOURCES := $(wildcard Sources/StudyTimerCore/*.swift)
APP_SOURCES := $(wildcard Sources/StudyFullTime/*.swift)
SWIFTFLAGS := -sdk "$(SDK)" -target "$(TARGET)"

.PHONY: build release debug app run test install clean

build: release

release:
	@mkdir -p $(BUILD)
	swiftc $(SWIFTFLAGS) -O -o $(BUILD)/StudyFullTime $(CORE_SOURCES) $(APP_SOURCES)
	codesign --force --sign - $(BUILD)/StudyFullTime

debug:
	@mkdir -p $(BUILD)
	swiftc $(SWIFTFLAGS) -Onone -g -o $(BUILD)/StudyFullTime-debug $(CORE_SOURCES) $(APP_SOURCES)
	codesign --force --sign - $(BUILD)/StudyFullTime-debug

app:
	./scripts/build-app.sh

run: app
	open "$(APP)"

test:
	@mkdir -p $(BUILD)
	swiftc $(SWIFTFLAGS) -Onone -g -o $(BUILD)/StudyTimerTests $(CORE_SOURCES) Tests/main.swift
	codesign --force --sign - $(BUILD)/StudyTimerTests
	./$(BUILD)/StudyTimerTests

install: app
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/StudyFullTime.app"
	cp -R "$(APP)" "$(HOME)/Applications/StudyFullTime.app"
	@echo "Installed $(HOME)/Applications/StudyFullTime.app"

clean:
	rm -rf $(BUILD)
