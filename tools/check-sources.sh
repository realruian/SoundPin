#!/bin/bash
# Source lists shared by inert previews and checks. Never include the app entry point.
MODEL_SOURCES=(SoundPin/Models/*.swift)
MANAGER_SOURCES=("${MODEL_SOURCES[@]}" SoundPin/Services/PriorityManager.swift SoundPin/Services/AudioManager.swift)
PREVIEW_SOURCES=("${MANAGER_SOURCES[@]}" SoundPin/Services/LaunchAtLoginManager.swift SoundPin/Views/*.swift tools/AudioTestSupport.swift tools/PreviewSupport.swift)
