import 'package:flutter/material.dart';

enum ExpenseCategory {
  fuel('Fuel', Icons.local_gas_station_outlined, Color(0xFFA15C00), Color(0xFFFFF1DC),
      {'petrol', 'diesel', 'fuel', 'cng', 'tel', 'pump'}),
  food('Food', Icons.restaurant_outlined, Color(0xFFB4470F), Color(0xFFFDE8E1),
      {'khana', 'lunch', 'dinner', 'breakfast', 'nashta', 'dhaba', 'food', 'thali', 'restaurant', 'biryani', 'baati'}),
  stay('Stay', Icons.bed_outlined, Color(0xFF2F55B5), Color(0xFFE4ECFB),
      {'hotel', 'room', 'rooms', 'stay', 'homestay', 'resort', 'hostel'}),
  toll('Toll', Icons.receipt_long_outlined, Color(0xFF4D555E), Color(0xFFEEF0F2),
      {'toll', 'parking', 'fastag'}),
  snacks('Snacks', Icons.local_cafe_outlined, Color(0xFF0E5E6F), Color(0xFFEEF6F7),
      {'chai', 'tea', 'coffee', 'snacks', 'poha', 'samosa', 'pani', 'water', 'cold', 'drink', 'maggi'}),
  tickets('Tickets', Icons.photo_camera_outlined, Color(0xFF7A4BB0), Color(0xFFF0E8F8),
      {'ticket', 'tickets', 'entry', 'fort', 'museum', 'boating'}),
  shopping('Shopping', Icons.shopping_bag_outlined, Color(0xFF8A3B5C), Color(0xFFF8E6EE),
      {'shopping', 'keychain', 'keychains', 'gift', 'kapde', 'souvenir'}),
  other('Other', Icons.more_horiz, Color(0xFF4D555E), Color(0xFFEEF0F2), {});

  const ExpenseCategory(this.label, this.icon, this.fg, this.bg, this.keywords);
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Set<String> keywords;

  static ExpenseCategory fromName(String name) =>
      ExpenseCategory.values.firstWhere((c) => c.name == name, orElse: () => ExpenseCategory.other);
}
