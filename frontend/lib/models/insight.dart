import 'package:flutter/material.dart';

class Insight {
  final String id;
  final String title;
  final String message;
  final String page; // 'dashboard', 'inventory', 'orders', 'menu', 'reports', 'general'
  final bool isImportant;
  final IconData icon;
  final Color color;
  final DateTime createdAt;

  Insight({
    required this.id,
    required this.title,
    required this.message,
    required this.page,
    this.isImportant = false,
    this.icon = Icons.info_outline,
    this.color = Colors.blue,
    required this.createdAt,
  });
}
