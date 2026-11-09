import 'package:flutter/material.dart';

class SeedPalette {
  const SeedPalette._();

  static const Color defaultSeed = Color(0xFF007AFF);

  // Prism UI's default accent colors, in its displayed order.
  static const List<int> defaultColors = [
    0xFF007AFF,
    0xFFCB30E0,
    0xFFFF2D55,
    0xFFFF383C,
    0xFFFF8D28,
    0xFFFFCC00,
    0xFF34C759,
    0xFF8E8E93,
  ];

  static const List<SeedColor> presets = [
    SeedColor('Blue', Colors.blue),
    SeedColor('Purple', Colors.purple),
    SeedColor('Green', Colors.green),
    SeedColor('Orange', Colors.orange),
    SeedColor('Pink', Colors.pink),
    SeedColor('Teal', Colors.teal),
    SeedColor('Red', Colors.red),
    SeedColor('Indigo', Colors.indigo),
    SeedColor('Amber', Colors.amber),
    SeedColor('Cyan', Color(0xFF00BCD4)),
  ];
}

@immutable
class SeedColor {
  const SeedColor(this.name, this.color);

  final String name;
  final Color color;
}
