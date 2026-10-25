import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../repositories/image_upload_repository.dart';
import '../widgets/app_navigation.dart';

class EventResultScreen extends StatelessWidget {
  const EventResultScreen({super.key, this.results = const []});
  final List<InferenceResult> results;

  @override
  Widget build(BuildContext context) {
    final occludedCount = results.where((r) => r.isOccluded).length;
    final changedCount = results
        .where((r) => r.isChanged && !r.isOccluded)
        .length;
    final isConfirmed = changedCount == 0 && occludedCount == 0;

    String summary;
    if (occludedCount > 0) {
      summary =
          '$occludedCount compartment(s) could not be verified (glare/blur/occlusion). '
          'Please retake the photo with better lighting and no lids blocking the view.';
    } else if (isConfirmed) {
      summary = 'Pill pattern matched the prescribed medication schedule.';
    } else {
      summary = '$changedCount compartment(s) differ from the baseline photo.';
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('Verification result'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      occludedCount > 0
                          ? Icons.visibility_off_rounded
                          : (isConfirmed
                                ? Icons.check_circle_rounded
                                : Icons.warning_amber_rounded),
                      size: 56,
                      color: occludedCount > 0
                          ? Colors.grey.shade700
                          : (isConfirmed
                                ? Colors.green.shade700
                                : Colors.orange.shade700),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      occludedCount > 0
                          ? 'Needs recapture'
                          : (isConfirmed ? 'Confirmed' : 'Changes detected'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(summary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: results.isEmpty ? 14 : results.length,
                itemBuilder: (_, i) {
                  final r = results.isEmpty ? null : results[i];
                  final occluded = r?.isOccluded ?? false;
                  final changed = r?.isChanged ?? false;
                  final Color background;
                  final Color border;
                  final Color text;
                  if (occluded) {
                    background = Colors.grey.shade300;
                    border = Colors.grey.shade700;
                    text = Colors.grey.shade900;
                  } else if (changed) {
                    background = Colors.red.shade100;
                    border = Colors.red.shade700;
                    text = Colors.red.shade900;
                  } else {
                    background = Colors.green.shade100;
                    border = Colors.green.shade700;
                    text = Colors.green.shade900;
                  }
                  return Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: background,
                      border: Border.all(color: border, width: 1.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          r == null ? '${i + 1}' : '${r.compartmentIndex + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: text,
                          ),
                        ),
                        if (occluded)
                          Icon(
                            Icons.visibility_off_rounded,
                            size: 14,
                            color: text,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/dashboard'),
              icon: const Icon(Icons.home_rounded),
              label: const Text('Return to dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
