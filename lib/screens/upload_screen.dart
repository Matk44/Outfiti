import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/outfit_tryon_provider.dart';
import '../widgets/image_upload_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/loading_overlay.dart';
import 'result_screen.dart';

class UploadScreen extends StatelessWidget {
  const UploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Consumer<OutfitTryOnProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const LoadingOverlay();
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload Images',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          ImageUploadCard(
                            label: 'Reference Hairstyle',
                            icon: Icons.face_retouching_natural,
                            image: provider.referenceImage,
                            onTap: () => _pickImage(
                              context,
                              isReference: true,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ImageUploadCard(
                            label: 'Your Selfie',
                            icon: Icons.person_outline,
                            image: provider.selfieImage,
                            onTap: () => _pickImage(
                              context,
                              isReference: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (provider.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        provider.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  PrimaryButton(
                    text: 'Generate',
                    onPressed: provider.canGenerate
                        ? () => _generateOutfit(context)
                        : null,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickImage(
    BuildContext context, {
    required bool isReference,
  }) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (image != null && context.mounted) {
      final bytes = await image.readAsBytes();
      final provider = context.read<OutfitTryOnProvider>();

      if (isReference) {
        provider.setReferenceImage(bytes);
      } else {
        provider.setSelfieImage(bytes);
      }
    }
  }

  Future<void> _generateOutfit(BuildContext context) async {
    final provider = context.read<OutfitTryOnProvider>();
    await provider.generateOutfit();

    if (context.mounted && provider.generatedImage != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const ResultScreen(),
        ),
      );
    }
  }
}
