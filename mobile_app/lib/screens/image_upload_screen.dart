import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../repositories/image_upload_repository.dart';
import '../repositories/medication_repository.dart';
import '../services/api_service.dart';
import '../widgets/app_navigation.dart';

/// Tracks the most recent uploaded photo event ID so it can be used as the
/// baseline for subsequent comparisons.
class _LastEventIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int value) => state = value;
}

final lastPhotoEventIdProvider = NotifierProvider<_LastEventIdNotifier, int?>(
  () => _LastEventIdNotifier(),
);

class ImageUploadScreen extends ConsumerStatefulWidget {
  const ImageUploadScreen({super.key});

  @override
  ConsumerState<ImageUploadScreen> createState() => _ImageUploadScreenState();
}

class _ImageUploadScreenState extends ConsumerState<ImageUploadScreen> {
  File? _selectedImage;
  bool _isBusy = false;
  String? _error;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final repo = ref.read(imageUploadRepositoryProvider);
      final picked = await repo.pickImage(source: source);
      if (picked == null) return;
      final compressed = await repo.compressImageFile(picked);
      setState(() {
        _selectedImage = compressed;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Could not access camera or gallery');
    }
  }

  Future<void> _verify() async {
    if (_selectedImage == null) {
      setState(() => _error = 'Select a photo first');
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });

    final int userId =
        ref.read(currentUserProvider)?.id ?? ref.read(userIdProvider);
    final repo = ref.read(imageUploadRepositoryProvider);
    final previousEventId = ref.read(lastPhotoEventIdProvider);

    try {
      final uploaded = await repo.uploadImage(
        userId: userId,
        imageFile: _selectedImage!,
      );
      final newEventId = uploaded.photoEventId;
      ref.read(lastPhotoEventIdProvider.notifier).set(newEventId);

      if (previousEventId == null) {
        // First capture — saved as baseline, no comparison available yet
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Baseline captured. Future verifications will compare against this.',
            ),
          ),
        );
        context.go('/dashboard');
        return;
      }

      final results = await repo.analyzePhoto(
        photoEventId: newEventId,
        baselineEventId: previousEventId,
      );
      if (!mounted) return;
      context.push('/event-result', extra: results);
    } on Exception catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Verification failed: $e';
      setState(() => _error = message);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previousEventId = ref.watch(lastPhotoEventIdProvider);
    final hasBaseline = previousEventId != null;

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Verify medication doses'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Image preview
            Expanded(
              child: _selectedImage != null
                  ? Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          _selectedImage!,
                          width: double.infinity,
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  : Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No photo selected',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hasBaseline
                                ? 'Capture current Adhera to compare'
                                : 'Take your first photo to set a baseline',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            // Camera / gallery row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isBusy
                        ? null
                        : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isBusy
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ],
            const SizedBox(height: 14),
            // Info chip showing baseline status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: hasBaseline
                    ? Colors.blue.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    hasBaseline
                        ? Icons.compare_arrows_rounded
                        : Icons.info_outline,
                    size: 16,
                    color: hasBaseline ? Colors.blue : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasBaseline
                          ? 'Will compare against your last captured photo'
                          : 'First capture: sets your Adhera baseline',
                      style: TextStyle(
                        fontSize: 12,
                        color: hasBaseline
                            ? Colors.blue.shade700
                            : Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isBusy || _selectedImage == null ? null : _verify,
                icon: _isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        hasBaseline
                            ? Icons.analytics_outlined
                            : Icons.photo_camera_rounded,
                      ),
                label: Text(
                  _isBusy
                      ? 'Processing...'
                      : (hasBaseline ? 'Verify doses' : 'Capture baseline'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
