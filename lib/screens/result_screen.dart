import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/outfit_tryon_provider.dart';
import '../widgets/primary_button.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OutfitTryOnProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: provider.generatedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            provider.generatedImage!,
                            fit: BoxFit.contain,
                            width: double.infinity,
                          ),
                        )
                      : Text(
                          'No result available',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                text: 'Try Another Outfit',
                onPressed: () {
                  provider.reset();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
