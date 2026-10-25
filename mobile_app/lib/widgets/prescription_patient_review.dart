import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../repositories/image_upload_repository.dart';
import 'prescription_image_preview.dart';

typedef PrescriptionDraft = ({
  String name,
  String dosage,
  String instructions,
  String note,
});

class PrescriptionPatientReview extends StatefulWidget {
  const PrescriptionPatientReview({
    super.key,
    required this.result,
    required this.onSubmit,
    required this.onScanAgain,
    this.image,
    this.preview,
  });
  final PrescriptionScanResult result;
  final File? image;
  final Uint8List? preview;
  final ValueChanged<PrescriptionDraft> onSubmit;
  final VoidCallback onScanAgain;
  @override
  State<PrescriptionPatientReview> createState() =>
      _PrescriptionPatientReviewState();
}

class _PrescriptionPatientReviewState extends State<PrescriptionPatientReview> {
  late final _nameCtrl = TextEditingController(
    text: widget.result.medicationName,
  );
  late final _dosageCtrl = TextEditingController(text: widget.result.dosage);
  late final _instructionsCtrl = TextEditingController(
    text: widget.result.instructions,
  );
  final _patientNoteCtrl = TextEditingController();
  bool _patientConfirmed = false;
  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _instructionsCtrl.dispose();
    _patientNoteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.preview != null) ...[
            FlattenedLabelPreview(image: MemoryImage(widget.preview!)),
            const SizedBox(height: 12),
          ],
          // Scanned image thumbnail
          if (widget.image != null) ...[
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(widget.image!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Info banner about the workflow
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_rounded, color: Colors.blue.shade600, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Review and correct any details below. Once you confirm, a pharmacist or connected care team member will verify this before the medication is added to your list.',
                    style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Prescription metadata (read-only)
          if (r.prescribedBy != null ||
              r.pharmacy != null ||
              r.refillsRemaining != null)
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'From label',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    if (r.prescribedBy != null)
                      _metaRow(
                        Icons.medical_services_outlined,
                        'Prescriber',
                        r.prescribedBy!,
                      ),
                    if (r.pharmacy != null)
                      _metaRow(
                        Icons.local_pharmacy_outlined,
                        'Pharmacy',
                        r.pharmacy!,
                      ),
                    if (r.refillsRemaining != null)
                      _metaRow(
                        Icons.refresh_rounded,
                        'Refills remaining',
                        r.refillsRemaining!,
                      ),
                  ],
                ),
              ),
            ),
          if (r.ocrProviderChain != null || r.requiresHumanReview == true)
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan quality',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    if (r.ocrProviderChain != null &&
                        r.ocrProviderChain!.isNotEmpty)
                      _metaRow(
                        Icons.layers_outlined,
                        'OCR providers',
                        r.ocrProviderChain!.join(' -> '),
                      ),
                    if (r.qualityGate != null &&
                        r.qualityGate!['reason'] != null)
                      _metaRow(
                        Icons.analytics_outlined,
                        'QC status',
                        r.qualityGate!['reason'].toString(),
                      ),
                    if (r.medicationNameMatched != null ||
                        r.medicationNameSource != null ||
                        r.medicationNameRxcui != null)
                      _metaRow(
                        Icons.medication_liquid_outlined,
                        'Name match',
                        [
                          if (r.medicationNameMatched != null)
                            (r.medicationNameMatched!
                                ? 'matched'
                                : 'unmatched'),
                          if (r.medicationNameConfidence != null &&
                              r.medicationNameConfidence!.isNotEmpty)
                            'confidence: ${r.medicationNameConfidence}',
                          if (r.medicationNameMatchScore != null)
                            'score: ${r.medicationNameMatchScore!.toStringAsFixed(2)}',
                        ].join('  •  '),
                      ),
                    if (r.medicationNameSource != null &&
                        r.medicationNameSource!.isNotEmpty)
                      _metaRow(
                        Icons.hub_outlined,
                        'Name source',
                        r.medicationNameSource!,
                      ),
                    if (r.medicationNameRxcui != null &&
                        r.medicationNameRxcui!.isNotEmpty)
                      _metaRow(
                        Icons.badge_outlined,
                        'RxCUI',
                        r.medicationNameRxcui!,
                      ),
                    if (r.requiresHumanReview == true)
                      _metaRow(
                        Icons.fact_check_outlined,
                        'Review',
                        'Required before auto-fill acceptance',
                      ),
                  ],
                ),
              ),
            ),
          // Editable fields
          Text(
            'Medication details',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Correct anything that was misread by the scanner',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Medication name',
              prefixIcon: Icon(Icons.medication_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dosageCtrl,
            decoration: const InputDecoration(
              labelText: 'Dosage',
              prefixIcon: Icon(Icons.scale_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instructionsCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Directions / instructions',
              prefixIcon: Icon(Icons.list_alt_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          // Note for reviewer
          Text(
            'Note for reviewer (optional)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _patientNoteCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'e.g. New medication, first time taking it',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          // Patient acknowledgment
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: _patientConfirmed
                    ? Colors.green.shade300
                    : Colors.grey.shade300,
              ),
              borderRadius: BorderRadius.circular(10),
              color: _patientConfirmed ? Colors.green.shade50 : null,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                value: _patientConfirmed,
                onChanged: (v) =>
                    setState(() => _patientConfirmed = v ?? false),
                title: const Text(
                  'I confirm these details are accurate to the best of my knowledge',
                ),
                subtitle: const Text(
                  'You are responsible for reviewing the extracted information before submission.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _patientConfirmed
                  ? () => widget.onSubmit((
                      name: _nameCtrl.text.trim(),
                      dosage: _dosageCtrl.text.trim(),
                      instructions: _instructionsCtrl.text.trim(),
                      note: _patientNoteCtrl.text.trim(),
                    ))
                  : null,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Submit for verification'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onScanAgain,
              icon: const Icon(Icons.document_scanner_rounded),
              label: const Text('Scan again'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
