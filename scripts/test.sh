#!/bin/bash
set -euo pipefail
ARCANINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ARCANINE_ROOT"
mkdir -p .build/tests/core .build/tests/notes .build/tests/motion .build/module-cache
ARCANINE_FLAGS=(-swift-version 5 -module-cache-path .build/module-cache)
cp Tests/core.swift .build/tests/core/main.swift
swiftc "${ARCANINE_FLAGS[@]}" Sources/ReminderCore.swift Sources/PetCharacter.swift Sources/Arcanine3DMotion.swift Sources/PetAnimationSupport.swift .build/tests/core/main.swift -o .build/tests/core-test
.build/tests/core-test
cp Tests/motion.swift .build/tests/motion/main.swift
swiftc "${ARCANINE_FLAGS[@]}" Sources/PetCharacter.swift Sources/Arcanine3DMotion.swift Sources/PetAnimationSupport.swift .build/tests/motion/main.swift -o .build/tests/motion-test
.build/tests/motion-test
swiftc "${ARCANINE_FLAGS[@]}" Sources/ReminderCore.swift Sources/PetCharacter.swift Sources/Arcanine3DMotion.swift Sources/PetAnimationSupport.swift Sources/CalendarParser.swift Sources/CalendarPayload.swift Sources/CalendarService.swift Tests/calendar.swift -o .build/tests/calendar-test
.build/tests/calendar-test
cp Tests/notes.swift .build/tests/notes/main.swift
swiftc "${ARCANINE_FLAGS[@]}" Sources/ReminderCore.swift Sources/PetCharacter.swift Sources/Arcanine3DMotion.swift Sources/PetAnimationSupport.swift Sources/CalendarParser.swift Sources/CalendarPayload.swift Sources/CalendarService.swift Sources/CalendarIntegration.swift Sources/MigaVoice.swift Sources/PetModel.swift .build/tests/notes/main.swift -o .build/tests/notes-test
.build/tests/notes-test
python3 Tests/characters.py
python3 Tests/arcanine-gait.py Assets/arcanine-biblioteca.glb
mkdir -p .build/tests/summoning
cp Tests/summoning.swift .build/tests/summoning/main.swift
swiftc "${ARCANINE_FLAGS[@]}" Sources/PetSummonTimeline.swift .build/tests/summoning/main.swift -o .build/tests/summoning-test
.build/tests/summoning-test
