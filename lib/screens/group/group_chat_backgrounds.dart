import 'package:flutter/material.dart';

/// Gradient hình nền khung chat nhóm (dùng chung Tùy chọn nhóm + màn chat).
class GroupChatBackgrounds {
  GroupChatBackgrounds._();

  static const int count = 16;

  static const List<String> labels = [
    'Mặc định',
    'Sky',
    'Mint',
    'Sunset',
    'Peach',
    'Lilac',
    'Ocean',
    'Meadow',
    'Rose',
    'Cloud',
    'Berry',
    'Sand',
    'Aqua',
    'Coral',
    'Leaf',
    'Night',
  ];

  static LinearGradient gradientAt(int index) {
    final i = index.clamp(0, count - 1);
    return gradients[i];
  }

  static const List<LinearGradient> gradients = [
    LinearGradient(
      colors: [Color(0xFFEDF2ED), Color(0xFFE3EBE3)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    LinearGradient(
      colors: [Color(0xFFE9FFF6), Color(0xFFD4F5E8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFFFF1E6), Color(0xFFFFDCC6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFFFF3E8), Color(0xFFFFD6BA)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFF2EDFF), Color(0xFFDCCEFF)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    LinearGradient(
      colors: [Color(0xFFE8F6FF), Color(0xFFCCE9FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFEFFBEF), Color(0xFFDCF3DC)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    LinearGradient(
      colors: [Color(0xFFFFEEF6), Color(0xFFFFD5E8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFF5F9FF), Color(0xFFE7EEF9)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    LinearGradient(
      colors: [Color(0xFFF7EDFF), Color(0xFFE4CBFF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFFFF7EA), Color(0xFFFFE7BF)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    LinearGradient(
      colors: [Color(0xFFE6FFFB), Color(0xFFC7F7ED)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFFFF0EB), Color(0xFFFFD8CB)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    LinearGradient(
      colors: [Color(0xFFF0FFF0), Color(0xFFD4F3D4)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFEEF2FF), Color(0xFFD8E2FF)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  ];
}
