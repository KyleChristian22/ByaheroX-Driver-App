import 'package:flutter/material.dart';
import '../../domain/entities/jeepney.dart';

class JeepInfoProvider extends ChangeNotifier {
  Jeepney? _selectedJeepney;
  bool _isExpanded = false;

  Jeepney? get selectedJeepney => _selectedJeepney;
  bool get isExpanded => _isExpanded;
  bool get hasSelection => _selectedJeepney != null;

  void selectJeepney(Jeepney jeepney) {
    _selectedJeepney = jeepney;
    _isExpanded = false;
    notifyListeners();
  }

  void clearSelection() {
    _selectedJeepney = null;
    _isExpanded = false;
    notifyListeners();
  }

  void toggleExpanded() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  void setExpanded(bool expanded) {
    _isExpanded = expanded;
    notifyListeners();
  }
}
