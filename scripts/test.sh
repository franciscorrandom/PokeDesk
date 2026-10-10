#!/bin/bash
set -euo pipefail
ARCANINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ARCANINE_ROOT"
mkdir -p .build/tests/core .build/tests/notes .build/tests/motion .build/module-cache
ARCANINE_FLAGS=(-swift-version 5 -module-cache-path .build/module-cache)
cp Tests/core.swift .build/tests/core/main.swift
swiftc "${ARCANINE_FLAGS[@]}" Sources/ReminderCore.swift Sources/PetAnimationSupport.swift .build/tests/core/main.swift -o .build/tests/core-test
.build/tests/core-test
cp Tests/motion.swift .build/tests/motion/main.swift
swiftc "${ARCANINE_FLAGS[@]}" Sources/Arcanine3DMotion.swift Sources/PetAnimationSupport.swift .build/tests/motion/main.swift -o .build/tests/motion-test
.build/tests/motion-test
swiftc "${ARCANINE_FLAGS[@]}" Sources/ReminderCore.swift Sources/CalendarParser.swift Sources/CalendarService.swift Tests/calendar.swift -o .build/tests/calendar-test
.build/tests/calendar-test
cp Tests/notes.swift .build/tests/notes/main.swift
swiftc "${ARCANINE_FLAGS[@]}" Sources/ReminderCore.swift Sources/PetAnimationSupport.swift Sources/Arcanine3DMotion.swift Sources/CalendarParser.swift Sources/CalendarService.swift Sources/CalendarIntegration.swift Sources/MigaVoice.swift Sources/PetModel.swift .build/tests/notes/main.swift -o .build/tests/notes-test
.build/tests/notes-test
