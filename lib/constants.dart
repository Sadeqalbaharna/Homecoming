// lib/core/constants.dart
import 'package:flutter/material.dart';

/// ===== Layout / Window =====
const double kSpriteSize = 170;
const double kRingPadding = 48;
const double kCanvasWidth = 560;
const double kCanvasHeight = 600;
const double kSpriteAlignY = 0.35;
const bool   kAlwaysOnTop  = false;

/// ===== Persona IDs =====
const String kPersonaKai   = 'kai';
const String kPersonaClone = 'clone';

/// ===== Timings =====
const Duration kAttentionPulse = Duration(milliseconds: 1200);

/// ===== Avatar GIF assets (ensure files + pubspec.yaml) =====
const String kAvatarIdleGif      = 'assets/avatar/idle.gif';
const String kAvatarAttentionGif = 'assets/avatar/attention.gif';
const String kAvatarThinkingGif  = 'assets/avatar/thinking.gif';
const String kAvatarSpeakingGif  = 'assets/avatar/speaking.gif';

/// ===== Visuals =====
const Color kRingColor = Color(0x66FFFFFF);
const Color kGlowColor = Color(0x33FFFFFF);
