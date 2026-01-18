import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/outfit_service.dart';

class OutfitTryOnProvider extends ChangeNotifier {
  final OutfitService _outfitService;

  OutfitTryOnProvider(this._outfitService);

  Uint8List? _referenceImage;
  Uint8List? _selfieImage;
  Uint8List? _generatedImage;
  bool _isLoading = false;
  String? _errorMessage;

  Uint8List? get referenceImage => _referenceImage;
  Uint8List? get selfieImage => _selfieImage;
  Uint8List? get generatedImage => _generatedImage;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get canGenerate => _referenceImage != null && _selfieImage != null;

  void setReferenceImage(Uint8List? image) {
    _referenceImage = image;
    _clearError();
    notifyListeners();
  }

  void setSelfieImage(Uint8List? image) {
    _selfieImage = image;
    _clearError();
    notifyListeners();
  }

  Future<void> generateOutfit() async {
    if (!canGenerate) return;

    _isLoading = true;
    _clearError();
    notifyListeners();

    try {
      final result = await _outfitService.generateOutfit(
        selfieImage: _selfieImage!,
        referenceImage: _referenceImage!,
      );

      _generatedImage = result;
    } catch (e) {
      _errorMessage = 'Unable to generate outfit. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void reset() {
    _referenceImage = null;
    _selfieImage = null;
    _generatedImage = null;
    _isLoading = false;
    _clearError();
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }
}
