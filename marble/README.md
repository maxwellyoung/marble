# Marble Maze Game - MVP

A physics-based marble maze game with pixel art aesthetics, haptic feedback, and sound effects.

## Features

- Tilt-based marble control using device accelerometer
- Multiple maze levels with increasing difficulty
- Goal collection mechanics
- Score tracking and time limits
- Pixel art visual style
- Haptic feedback for enhanced kinaesthetic experience
- Sound effects for immersive gameplay

## Getting Started

### Prerequisites

- Xcode 12.0 or later
- iOS 14.0 or later
- Physical iOS device (for accelerometer and haptic feedback)

### Installation

1. Clone the repository
2. Open the project in Xcode
3. Add sound files to the Sounds directory (see Sounds/README.md for details)
4. Build and run on a physical iOS device

## Game Controls

- Tilt your device to move the marble
- Navigate through the maze to collect all goals
- Complete levels within the time limit to advance

## Sound and Haptic Feedback

The game features rich sound and haptic feedback for an immersive experience:

- Rolling sounds as the marble moves
- Collision sounds when hitting walls
- Success sounds when reaching goals
- Haptic feedback synchronized with game events
- Sound and haptic settings can be toggled in the start screen

## Debugging

The game includes debugging features to help validate sound and haptic implementation:

- Console logs for sound loading and playback
- Haptic feedback event logging
- Sound manager status reporting

## Known Issues

- Sound files need to be added manually (see Sounds/README.md)
- Haptic feedback may be rate-limited on some devices
- Accelerometer sensitivity may vary across different device models

## Next Steps

- Add more complex maze levels
- Implement obstacles and moving elements
- Add power-ups and special abilities
- Create a level editor
- Add persistent high scores
- Implement background music
- Add visual effects for collisions and goal collection
