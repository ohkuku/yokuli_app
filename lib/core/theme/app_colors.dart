import 'package:flutter/material.dart';

/// Yokuli maritime color palette
class AppColors {
  AppColors._();

  // --- Backgrounds ---
  static const background = Color(0xFF07111F);
  static const surface = Color(0xFF0D1E35);
  static const surfaceElevated = Color(0xFF112540);
  static const cardBg = Color(0xFF152D4A);
  static const dialogBg = Color(0xFF0F2038);

  // --- Accents ---
  static const cyan = Color(0xFF00D9FF);
  static const cyanDim = Color(0xFF0099BB);
  static const teal = Color(0xFF00B4A0);
  static const blue = Color(0xFF0A84FF);

  // --- Status ---
  static const success = Color(0xFF30D158);
  static const warning = Color(0xFFFFD60A);
  static const danger = Color(0xFFFF453A);
  static const inactive = Color(0xFF3A5A72);

  // --- Text ---
  static const textPrimary = Color(0xFFE8F4FD);
  static const textSecondary = Color(0xFF8BABBF);
  static const textMuted = Color(0xFF4D7A96);
  static const textDim = Color(0xFF2E566E);

  // --- Borders / Dividers ---
  static const border = Color(0xFF1A3D5A);
  static const divider = Color(0xFF112236);

  // --- Module accent colors (for tile gradients) ---
  static const modSignalK = Color(0xFF0A84FF);
  static const modDashboard = Color(0xFF30D158);
  static const modPower = Color(0xFFFFD60A);
  static const modLogbook = Color(0xFF5E5CE6);
  static const modSafety = Color(0xFFFF453A);
  static const modMaintenance = Color(0xFFFF9F0A);
  static const modWeather = Color(0xFF64D2FF);
  static const modTools = Color(0xFF636366);

  // --- Instrument gauge fills ---
  static const gaugeTrack = Color(0xFF1A3D5A);
  static const gaugeNormal = cyan;
  static const gaugeWarning = warning;
  static const gaugeDanger = danger;
}
