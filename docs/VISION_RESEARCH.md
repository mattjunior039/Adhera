# Vision Research: Pillbox Video Verification

This is the engineering log for Adhera's video dose-verification models: how
the data was prepared and labeled, how the models were trained and evaluated,
what worked, what failed, and why. In the code and scripts, this work is called
the **official prototype** (`official_*` modules, `runs/official_blue_pm/`).

## Summary

| | |
| --- | --- |
| **Goal** | From a short video of a pillbox, detect which compartment a pill was taken from, without being told what to expect. |
| **Setup** | One row of seven blue PM compartments, Sunday to Saturday from left to right. Three medications: acetaminophen, ibuprofen, and iron. |
| **Models** | A YOLOv8 compartment segmentation model and a YOLOv8 3-class pill detector (`corrected_batch_01`). |
| **Method** | Count pills per compartment in a stable *before* period and a stable *after* period, then compare the per-medication counts across the seven days. |
| **Result** | 3 of 4 reviewed development recordings were correct when the before and after periods were marked by hand (2 of 3 removals and 1 of 1 transfers). Automatic period selection got 0 of 4. These are development recordings, not an independent test. |
| **Safety** | Results are candidates that always require review. The schedule is never given to the models, and inventory and adherence are never changed automatically. |
| **Next steps** | More recording sessions with clear still periods and "no removal" examples, then reliable automatic detection of the before and after periods. |

## Contents

1. [Scope and current status](#scope-and-current-status)
2. [Prepare annotation candidates](#prepare-annotation-candidates)
3. [What to annotate manually](#what-to-annotate-manually)
4. [Recommended new algorithm](#recommended-new-algorithm)
5. [Train and evaluate after annotation](#train-and-evaluate-after-annotation)
6. [Limited-label pilot (October 15)](#limited-label-pilot-october-15)
7. [Polygon and video evaluation](#polygon-and-video-evaluation)
8. [Corrected annotation batch: October 16 training](#corrected-annotation-batch-october-16-training)
9. [Target-medication comparison and API integration](#target-medication-comparison-and-api-integration): **the current runtime design**

---

## Scope and current status

The October 15 recordings in the local `Downloads/data` folder are the official
prototype data. Do not mix earlier prototype images, labels, checkpoints, or
classifier training crops into this experiment.

- One visible row of **seven compartments**, not the old 2 x 7 layout.
- Blue identifies **PM** for this prototype.
- Viewed in the intended upright orientation, columns are **Sunday through
  Saturday, left to right**.
- The known pills are **acetaminophen, ibuprofen, and iron**.
- The initial assumption was one pill removed per clip. Review corrected
  clip 3 to a **Wednesday-to-Tuesday ibuprofen transfer**, not a net removal.
  Verify each outcome rather than forcing every prediction to match the assumption.

The preparation command below works without ML dependencies. A limited-label
pill detector, compartment segmenter, and experimental video comparator have
now been trained and evaluated locally; see [video evaluation](#polygon-and-video-evaluation).
The API and app now use the updated models through a **review-only,
acetaminophen/ibuprofen-scoped comparator**. See
[current integration](#target-medication-comparison-and-api-integration).
The historical strict whole-box results below remain for comparison.
Do not deploy the old two-row video checkpoint with these recordings.

## Prepare annotation candidates

Run from the repository root:

```bash
python3 -m backend_api.scripts.training.prepare_official_prototype \
  --source /Users/matthew/Downloads/data \
  --output /Users/matthew/Downloads/pillbox_official_annotation
```

Requires `ffmpeg` and `ffprobe` on PATH. Source videos are read, never modified.
The command refuses an existing output directory to protect manual labels.

By default, 12 evenly spaced candidates are extracted per recording at native
resolution: 684 images for the current 57 clips. These are **candidates**, not
automatically accepted training images. No pill identity or split is inferred.

Output:

| Item | Purpose |
| --- | --- |
| `images/` | JPEG candidates with unique clip/frame names. |
| `annotation_images.zip` | Those same images, ready to import into an annotation tool. |
| `obj.names` | Fixed YOLO class order. |
| `prototype.json` | The explicit prototype layout and class specification. |
| `video_manifest.csv` | Video hashes, session/split assignments, and human ground truth. |
| `frame_manifest.csv` | Candidate timestamps and human keep/reject decisions. |

Uniform sampling can miss a short clear before/after view. Use the original
video to locate those views; add frames if the initial candidates miss them.
Prefer the original camera videos over screen recordings if available:
screen recordings add overlays and compression, and may lose useful detail.

One recording needs particular review: `Screen Recording 2026-10-15 214347.mp4`
(`clip_051`) is 258.7 seconds long. Widely spaced inspected samples look nearly
static; do not assume it contains a removal or include repeated views as
independent examples. Check the complete clip and mark its actual outcome.

## What to annotate manually

Use CVAT locally, or another bounding-box editor that exports YOLO detection
labels. Do not upload footage to a hosted service unless you deliberately choose
to share it. Start with **5-10 clips**, check annotation quality, then expand.

Create these labels in exactly this order:

| ID | Label | Box |
| --- | --- | --- |
| 0 | `acetaminophen` | Tight rectangle around each visible known acetaminophen pill. |
| 1 | `ibuprofen` | Tight rectangle around each visible known ibuprofen pill. |
| 2 | `iron` | Tight rectangle around each visible known iron pill. |
| separate model | `compartment` | Polygon around each visible open interior, excluding lid and exterior. |

Keep pill rectangles and compartment polygons in separate exports. YOLO pill
IDs are 0-2; COCO numeric IDs depend on the export and must be resolved by
category name, not copied as YOLO IDs.
The original candidate package included a fourth `compartment` name from the
earlier rectangle-only plan; do not include it in the three-class pill export.
New preparation outputs use the separate-model convention.

Confirm pill-to-class identity from the verified packaging and your recording
notes, not by guessing from color. Obtain reference photos of each exact pill
type, both sides and imprint, with package name/strength recorded separately.
These labels describe these specific prototype pills, not all brands or forms
of the medication.

For each retained frame:

1. Include sharp, open, unobstructed views **before and after** extraction.
   Aim for 2-4 useful views of each phase per clip, if available.
2. Draw boxes around **every visible pill**, not just the one being removed.
   Missing labels teach the detector to ignore real pills.
3. Draw all seven compartment-interior polygons, including empty compartments.
   Keep the interior boundary convention consistent across views.
4. Reject blurred, severely glared, clipped, closed-lid, or hand-obscured views
   from the initial counting dataset. Do not label an unreadable compartment
   as empty. Keep those original video intervals for later abstention testing.
5. Keep only views where medication identity and count can be labeled reliably.
   An image with no pills but seven clearly visible empty interiors is a valid
   negative example. A closed lid is not such an example.
6. Mark `keep` as `yes` or `no` in `frame_manifest.csv`. Import only retained
   images for annotation; the supplied ZIP contains all candidates.

Export pills as **YOLO detection bounding boxes**; check `obj.names` against the
three pill classes above. One label file must match each retained image's basename.
Export compartments as **COCO segmentation polygons**, with category
`compartment`. The supplied pink polygons are already usable; do not redraw them
as rectangles. Perspective makes neighboring axis-aligned rectangles overlap.
See [CVAT's YOLO format documentation](https://docs.cvat.ai/docs/dataset_management/formats/format-yolo/).

### Per-video ground truth

Fill `video_manifest.csv` while watching the original clips:

- `removed_day`: `SUN`, `MON`, `TUE`, `WED`, `THU`, `FRI`, or `SAT`.
- `removed_class`: `acetaminophen`, `ibuprofen`, or `iron`.
- `removed_count`: actual number that left the box, not a default assumption.
- `event_type`: human-reviewed event, e.g. `SINGLE_REMOVAL`, `TRANSFER`, or
  `NO_CHANGE`. For transfers, fill `source_day`, `destination_day`,
  `transferred_class`, and `transferred_count`; `removed_count` is 0.
  Newly prepared manifests leave all ground truth blank. Older manifests
  prefilled `removed_count=1`, which must be reviewed rather than trusted.
- `before_start_seconds`, `before_end_seconds`: a clear, open interval before
  removal, not the initial closed-lid view.
- `after_start_seconds`, `after_end_seconds`: a clear, open interval after the
  hand leaves, before the lid closes.
- `session_id`: recordings sharing the same setup/take sequence must be grouped.
  Consecutive clips of the same pill arrangement should not be treated as
  independent just because they have different filenames.
- `split`: `train`, `val`, or `test`, assigned to whole sessions.

If a clip has no readable before/after interval, note that limitation and keep
it as a difficult/abstention example rather than inventing a label.

Target roughly 70% train / 15% validation / 15% held-out test **by independent
session**, while covering all three pill classes and all seven days where the
recordings allow. Never randomly split extracted frames. If these clips are one
continuous setup with near-identical arrangements, collect independent sessions
for evaluation; a random video split can still give misleading accuracy.

## Recommended new algorithm

Use a **three-class pill detector plus a one-class compartment segmenter**,
followed by a deterministic temporal count comparison. The supplied polygons
allow pill centers to be assigned to actual interiors instead of overlapping
bounding rectangles. This is separate from the old generic pill detector plus
two-class crop classifier. If the pill classes remain visually ambiguous,
evaluate a crop classifier next.

1. **Find readable open views across the entire clip.** Closed endpoints must
   not become the before/after reference. Sample the complete duration, not just
   the first fixed number of frames.
2. **Localize seven compartment interiors per usable frame.** Sort centers
   left-to-right and map them to `SUN_PM` through `SAT_PM`. Reject incomplete,
   overlapping, or ambiguous geometry. Do not split a picture containing the lid
   into a 2 x 7 grid. Do not infer AM from blue.
3. **Assign pill detections to compartments.** Use a pill's center in exactly one
   compartment interior, rejecting ambiguous assignments. Re-localize or track
   the row as the camera moves rather than reusing a stale transform.
4. **Build a seven-by-three count vector per readable frame.** Exclude occluded
   or unreadable views; absence of a detection alone does not prove emptiness.
5. **Compare stable before/after windows.** Require agreement across multiple
   clear views in each phase. Thresholds and window length must be chosen using
   validation recordings, not the held-out test clips.
6. **Report the actual delta.** A confident single-pill event requires exactly
   one `(day, medication)` count to fall by one, with all other counts unchanged.
   A same-class decrease in one cell and increase in another is instead a
   `CANDIDATE_TRANSFER`, with source/destination days and zero net removals.
   Do not use the claimed schedule to force the detected compartment.
7. **Abstain explicitly.** Missing clear phases, uncertain pill identity,
   inconsistent counts, camera misalignment, or competing changes produce
   `INCONCLUSIVE`. Stable unchanged counts produce `NO_COUNT_CHANGE`.
   Multiple removals/additions should be reported separately, not forced into
   a one-pill success.

The experimental implementation follows this specification with provisional
thresholds: at least three agreeing complete count vectors and 75% within-phase
agreement. Automatic mode compares the first and last 1.5-second accepted-frame
windows. A simple HSV hand-color heuristic is only a quality guard, not a
validated hand/occlusion detector.

## Train and evaluate after annotation

Use a fresh checkpoint/output directory, e.g.
`backend_api/runs/official_blue_pm/`, never the legacy model path.
Build the training dataset from **kept, annotated frames** and the reviewed
session-level split manifest. Explicitly distinguish missing annotations from
valid empty label files; never silently turn unlabeled pills into negatives.

Train a small YOLO detection model first, retaining the best validation
checkpoint. Evaluate:

- Per-class detection precision/recall and confusion, including iron.
- Per-compartment before/after count accuracy.
- Exact video-level match of **day + medication + quantity**.
- False-removal rate and inconclusive rate, not just detector mAP.
- Performance by day, pill type, lighting, and recording session.

The first four reviewed clips contain three removals and one confirmed transfer.
Add separate recordings with no change, a hand opening/closing without removal,
multiple removals, additions, and unreadable/occluded scenes before claiming
reliable event verification.
Check that no-removal recordings remain unchanged or inconclusive.

Pill removal is visual evidence of removal, **not proof of ingestion or medical
identity**. A working prototype must preserve that distinction in its API/UI.

The full pipeline still needs independent-session annotations, negative
recordings, and calibration before API integration. The four-clip development
evaluation below is not sufficient to establish reliability.

## Limited-label pilot (October 15)

A separate experimental detector has now been trained from the first export.
This initial pilot was a three-pill **image detector and manually selected
before/after comparison**. The later polygon/video extension is evaluated below.
At this pilot stage, the API and its legacy checkpoint were unchanged; the
later integration section supersedes that status.

### Data audit and actual results

- 26 labeled images across `clip_001` through `clip_004`; all numeric IDs match
  the screenshot: `0=acetaminophen`, `1=ibuprofen`, `2=iron`.
- No compartments were included in this rectangle-only export. The later COCO
  JSON contains the compartment polygons.
- One accidental zero-height box was excluded explicitly in the generated copy,
  leaving **499 usable boxes**; original labels were not changed.
- 23 images from clips 1-3 trained the model; 3 images from clip 4 provided
  preliminary validation. These recordings are **not established as independent
  sessions**, so this split cannot establish generalization.
- YOLOv8n fine-tuning ran for 40 epochs at 640 pixels using Apple MPS.
- The best checkpoint's three-image validation mAP@50 was **0.836**;
  mAP@50-95 was **0.377**. These are detection metrics on an extremely small,
  potentially correlated validation set, not removal accuracy.
- At confidence 0.5, held-out frame counts still varied and missed pills.
  A real before/after smoke test on clip 1 returned **`INCONCLUSIVE`** because
  the two pre-removal detections disagreed. It did not invent a removal.
- At that stage human video outcomes were unavailable. Four user-confirmed
  outcomes are now stored separately in the local evaluation cases file.

Local artifacts (gitignored):

- Dataset: `/Users/matthew/Downloads/pillbox_official_pilot_dataset/`
- Checkpoint: `backend_api/runs/official_blue_pm/pilot_01/weights/best.pt`
- Visual detection examples: `backend_api/runs/official_blue_pm/pilot_01/predictions/`
- Comparison output: `backend_api/runs/official_blue_pm/pilot_01/comparison_smoke_test.json`

### Reproduce the pilot

Use Python 3.12 and an isolated environment; the full API dependency stack is
not required:

```bash
python3.12 -m venv .venv-vision
.venv-vision/bin/python -m pip install -r backend_api/requirements-official-vision.txt

.venv-vision/bin/python -m backend_api.scripts.training.official_detector prepare \
  --labels /Users/matthew/Downloads/labels_my-project-name_2026-10-15-11-41-46 \
  --images /Users/matthew/Downloads/pillbox_official_annotation/images \
  --output /Users/matthew/Downloads/pillbox_official_pilot_dataset_v2 \
  --validation-clips clip_004 \
  --drop-zero-area-boxes

.venv-vision/bin/python -m backend_api.scripts.training.official_detector train \
  --dataset /Users/matthew/Downloads/pillbox_official_pilot_dataset_v2/dataset.yaml \
  --output backend_api/runs/official_blue_pm/pilot_next \
  --epochs 40 --device mps
```

Use new dataset/run paths to avoid overwriting earlier work. Use `--device cpu`
if MPS is unavailable. Initial training downloads public pretrained weights;
training itself is local. Only images with matching label files enter the
dataset; missing annotations are never fabricated as background labels.
`audit.json` records class counts and every zero-area exclusion.
The current training command uses a frozen ten-layer backbone, AdamW, and
learning rate 0.001. This differs from the original `pilot_01` default-optimizer
run. A second run requested 120 epochs, stopped after 49 (best epoch 34), and
achieved mAP@50 0.843 / mAP@50-95 0.359. It did not improve video-level success.

To compare **manually reviewed, open, unobstructed views of the same visible
area**:

```bash
.venv-vision/bin/python -m backend_api.scripts.training.official_detector compare \
  --checkpoint backend_api/runs/official_blue_pm/pilot_01/weights/best.pt \
  --before /path/to/before_1.jpg /path/to/before_2.jpg \
  --after /path/to/after_1.jpg /path/to/after_2.jpg \
  --confirmed-clear-views --device mps
```

This command outputs JSON with per-image boxes/counts and a review-only result.
It requires at least two distinct images per phase and exact within-phase count
agreement. A single-class decrease of one produces `CANDIDATE_SINGLE_REMOVAL`;
conflicting counts produce `INCONCLUSIVE`. Unchanged counts produce
`NO_COUNT_CHANGE`, not a claim that no removal occurred. Every output requires
human review. The confidence threshold is provisional, not calibrated.

It compares the entire supplied image. You can provide manually prepared crops
of the same compartment, but do not compare different crops or camera coverage.
It does **not** determine the weekday, automatically select clear phases, or
detect hand occlusion. `day` stays null rather than guessing from pill position.
Consistent counts can still be consistently wrong.

### Highest-value next annotations

More data is needed for reliable removal verification, but not thousands of
near-identical frames. Prioritize:

1. Correct the current labels: remove accidental boxes, label every clearly
   visible pill consistently, and do not use unreadable views for exact counts.
2. Annotate clear before/after pairs from another **6-10 clips**, ideally from
   different recording sessions, covering all three removed medications.
3. Include all **seven compartment interiors** if automatic day identification
   is required. Export `compartment` polygons separately as COCO, not as an extra
   class in the three-class pill dataset.
4. Fill in removed day/class and before/after intervals in `video_manifest.csv`.
5. Add no-removal and hand-occluded clips to assess false positives and abstention.

## Polygon and video evaluation

### New annotation audit

The supplied `labels_my-project-name_2026-10-15-11-55-37.json` contains **66
compartment polygons across 10 images** from clips 1 and 2. Its COCO IDs are
1=acetaminophen, 2=ibuprofen, 3=iron, 4=compartment; actual annotations in this
file are compartment-only. Pill rectangles still come from the earlier export.

Eight images contain all seven compartments. Two incomplete images were
excluded explicitly: `clip_001_frame_007` has six polygons;
`clip_002_frame_006` has four. The preparation audit records these exclusions;
missing polygons are not treated as absent compartments. Originals are unchanged.

The segmentation dataset has **4 training images / 28 polygons** from clip 1
and **4 validation images / 28 polygons** from clip 2. YOLOv8n-seg trained
for 150 epochs at 640 pixels, batch 4, frozen ten-layer backbone, AdamW 0.001.
Validation mask mAP@50 was **0.995**, mAP@50-95 **0.711**. These four correlated
validation images do not establish independent-session performance.

An earlier rectangle-compartment model had mAP@50 0.987, but its overlapping
rectangles made pill-to-day assignment ambiguous. Using the actual polygons
reduced that geometry problem; it did not solve unstable pill detections.

### Actual four-video results

Ground truth below was supplied by the user, not generated by the detector.
Both complete-video automatic sampling and manually reviewed phase intervals
were tested at 2 samples/second.

| Source recording suffix | Confirmed event | Automatic | Assisted timing |
| --- | --- | --- | --- |
| 205200 / clip 1 | MON acetaminophen | INCONCLUSIVE | INCONCLUSIVE |
| 205322 / clip 2 | FRI ibuprofen | INCONCLUSIVE | INCONCLUSIVE |
| 205454 / clip 3 | Ibuprofen transferred WED -> TUE | INCONCLUSIVE | INCONCLUSIVE |
| 205612 / clip 4 | MON acetaminophen | INCONCLUSIVE | INCONCLUSIVE |

For **each mode**, exact event success was **0/4 (0.0%)**: confirmed removal
success **0/3 (0.0%)**, and transfer identification **0/1 (0.0%)**. Coverage
was **0.0%**, and all four clips were inconclusive. A transfer match requires
the correct medication, source, destination, and quantity; reporting it as a
net removal would be incorrect.
Candidate precision is **undefined**, because there were no candidate
predictions. Zero incorrect candidates is not evidence of a low false-positive
rate: this evaluation contains only one transfer and no unchanged/hand-only clips.

The original pill detector plus segmentation accepted the following sampled
frames for counting. Accepted means valid detected geometry/assignment and
passing the provisional hand guard, not verified correct pill counts:

| Clip | Automatic accepted / sampled | Assisted accepted / sampled | Before / after joint-vector agreement, assisted |
| --- | --- | --- | --- |
| 1 | 20/40 | 9/9 | 25% / 100% |
| 2 | 4/27 | 4/8 | insufficient frames / insufficient frames |
| 3 | 95/103 | 7/7 | 66.7% / 75% |
| 4 | 10/26 | 7/8 | 75% / 66.7% |

A second pill-training run with more conservative fine-tuning also returned
0/4 in each mode. Its slightly higher detection mAP did not translate into
better removal identification. Do not select a checkpoint using these four
outcomes and then describe the same clips as unseen tests.

These are **development results**, not generalization accuracy: the pill model
trained on clips 1-3 and selected weights using clip 4. The compartment model
trained on clip 1 and selected weights using clip 2. There are no independent
test sessions, no iron-removal outcome among these four cases, and no
unchanged/hand-only negative clips.

### Precisely what failed

1. **The initial event assumption was wrong for one clip.** In assisted clip 3,
   Tuesday ibuprofen is detected as 1 before and 2 after in every accepted
   frame, while Wednesday's modal ibuprofen count falls from 3 to 2. Reviewing
   this prompted user confirmation that the pill was moved WED -> TUE.
   This is not evidence of a pill taken, nor should the addition automatically
   be blamed on detection error. The comparator now distinguishes a stable
   same-class transfer from a net removal.
2. **Whole-row consensus is fragile.** It compares 21 counts, so errors in
   unrelated compartments invalidate otherwise plausible local evidence.
   In clip 1, no complete before-count vector repeats (25% support).
   In clip 4, the full after vector repeats in only 2/3 frames, below the
   required three agreeing frames / 75% threshold.
   False/missed/class-confused detections remain possible; the exact cause
   of each unstable count needs comparison with complete frame annotations.
3. **Readable geometry is not always available.** In automatic clip 2,
   21/27 samples fail the seven-compartment geometry check and two trigger
   the hand guard; only two accepted samples remain in each comparison phase.
   Incomplete rows, duplicate compartment predictions, hands, and moving
   views cannot be treated as empty cells.
4. **Timing and recording quality matter.** Automatic endpoints can select
   moving, glared, or partially open views. Assisted timing still fails, so
   better endpoint selection alone is not a fix. Clip 3 is almost static for
   much of its middle and needs review of the original recording for frozen
   or repeated footage; repeated frames are not independent evidence.

There is **qualitative signal, not verified event accuracy**: with
manually selected phases, the original detector's modal local counts show
MON acetaminophen 2->1 in clip 1, WED ibuprofen 3->2 together with TUE
ibuprofen 1->2 in clip 3, and MON acetaminophen 1->0 in clip 4.
Clip 2 has only two accepted views per phase
and tied after counts. These are post-hoc diagnostics, not additional correct
predictions; mode ties/competing changes and unstable views prevent confirmation.

### Highest-priority remedies

1. Finish the missing compartment polygons in the two incomplete images and
   check every pill rectangle against the raw frame. Label all visible pills
   consistently, including touching/partly overlapping pills when readable.
2. Annotate **4 clear before + 4 clear after frames from another 6-10 clips**
   as a next collection batch, not a promise of sufficient data. Cover all
   three medications and seven days across independent sessions, with at least
   two seconds of stationary, unobstructed video per phase. Use overhead framing,
   keep all seven cells visible, avoid glare, and prefer camera originals.
3. Reserve complete new sessions for validation and untouched testing before
   training. Include iron removals, no-removal/hand-only clips, additions,
   multiple removals, and difficult views. Record their actual day/class/count.
4. Evaluate **perspective-aligned compartment crops plus temporal pill tracking**
   to improve small-pill resolution and distinguish a persistent object from
   a one-frame missed detection. Consider per-compartment evidence with explicit
   uncertainty instead of requiring a perfect whole-row vector, but calibrate
   this on separate validation sessions with negatives before loosening checks.
5. Replace the provisional HSV hand guard with a validated occlusion/quality
   check. Do not remove abstention merely to make these four clips succeed.

At this evaluation stage, the experimental comparator was not wired into the
app/API. Later integration does not establish medication identity or ingestion.

### Reproduce compartment training and video scoring

From the repository root, after installing the isolated vision requirements:

```bash
.venv-vision/bin/python -m backend_api.scripts.training.official_compartments \
  --coco /Users/matthew/Downloads/labels_my-project-name_2026-10-15-11-55-37.json \
  --images /Users/matthew/Downloads/pillbox_official_annotation/images \
  --dataset-output /Users/matthew/Downloads/pillbox_official_compartments_next \
  --run-output backend_api/runs/official_blue_pm/compartments_seg_next \
  --epochs 150 --device mps

.venv-vision/bin/python -m backend_api.scripts.training.evaluate_official_videos \
  --cases backend_api/runs/official_blue_pm/evaluation_cases.json \
  --pill-checkpoint backend_api/runs/official_blue_pm/pilot_01/weights/best.pt \
  --compartment-checkpoint backend_api/runs/official_blue_pm/compartments_seg_01/weights/best.pt \
  --output backend_api/runs/official_blue_pm/video_evaluation_next.json \
  --device mps

.venv-vision/bin/python -m unittest \
  backend_api.tests.test_official_video_detection \
  backend_api.tests.test_official_detector \
  backend_api.tests.test_prepare_official_prototype -v
```

Use fresh output paths. `official_compartments` currently assigns only clip 1
to training and clip 2 to validation; adding clips requires an explicit split
change, not a silent random frame split.

The local `evaluation_cases.json` is a list of objects with `clip`, `video`,
`expected_event_type` (`SINGLE_REMOVAL` or `TRANSFER`), `expected_day`
(source day), `expected_class`, `windows` (two `[start,end]` intervals),
`pill_training_overlap`, and `compartment_training_overlap`. The overlap flags
mean training exposure only; clip 4/clip 2 validation exposure is disclosed
separately above. Expected day/class are used only by scoring and are never
passed to inference. Transfers additionally require `expected_destination_day`.
The automatically selected phases never use those intervals.
The report records all sampled predictions/rejections, selected timestamps,
agreement ratios, model/case SHA-256 hashes, and separate automatic/assisted
metrics. Input hashes provide provenance, not a guarantee of deterministic MPS
training or inference.

Local artifacts are gitignored:

- Primary corrected evaluation: `backend_api/runs/official_blue_pm/video_evaluation_corrected_pill01.json`
- Second pill-model evaluation: `backend_api/runs/official_blue_pm/video_evaluation_corrected_pill02.json`
- Reviewed outcomes/timing: `backend_api/runs/official_blue_pm/evaluation_cases.json`
- Compartment masks: `backend_api/runs/official_blue_pm/compartments_seg_01/weights/best.pt`
- Original pill model: `backend_api/runs/official_blue_pm/pilot_01/weights/best.pt`
- Second pill model: `backend_api/runs/official_blue_pm/pilot_02/weights/best.pt`
- Raw timing contact sheets: `backend_api/runs/official_blue_pm/video_review/`
- Polygon/pill/count review sheets: `backend_api/runs/official_blue_pm/video_review_seg_final/`

Earlier `video_evaluation_seg_*` and `video_evaluation_final_*` reports predate
the transfer clarification. They remain as historical artifacts, not the
authoritative scoring. The corrected reports use the updated human event labels.
The focused validation suite currently passes **46 tests**, including transfers,
sampling/decode failures, polygon conversion, and scoring isolation from truth.

Generated weights/data are deliberately not submission source files; preserve
them locally or distribute as a separate versioned artifact when required.

## Corrected annotation batch: October 16 training

Training proceeded with the user's explicit approval to retain the remaining
annotation-quality concerns. No input labels were modified. The Roboflow export
contains 18 reannotated images with class order `acetaminophen, compartment,
ibuprofen, iron`; generated pill labels remap IDs `0->0, 2->1, 3->2` and exclude
the compartment rows from the pill task. The separate existing COCO polygons
remain the segmentation source, not the new axis-aligned compartment rectangles.

The 18 revised pill labels replace their corresponding labels in the 48-image
crop batch; the other 30 crop labels are retained. The original 26 labeled
full-frame images are included separately, without changing crop coordinates.
Validation holds out complete clips, but session independence is not established.

| Task | Train | Validation | Training |
| --- | --- | --- | --- |
| Three-class pill detection | 63 images / 1,342 boxes | 11 images / 240 boxes, clips 004 and 017 | YOLOv8n, best weights from a 55-epoch run (120 requested, early stopping) |
| Compartment segmentation | 44 images / 308 polygons | 12 images / 84 polygons, clips 002 and 017 | YOLOv8n-seg, resumed after tool timeout and stopped at epoch 40 |

Both use 640-pixel inputs, batch 4, seed 42, frozen first 10 layers, AdamW
learning rate 0.001, and no flips/mosaic. Pill validation precision is **0.937**,
recall **0.959**, mAP@50 **0.957**, and mAP@50-95 **0.447**. Compartment mask
mAP@50 is **0.995**, mAP@50-95 **0.812**. These are label-based model-selection
metrics, not event accuracy. Exact three-class image counts at confidence 0.5
match the supplied validation annotations on only **3/11 images (27.3%)**.

### Event tests

The original four human-labeled development videos still return `INCONCLUSIVE`
in both automatic and assisted timing modes: **0/4 exact events**, **0/3
removals**, **0/1 transfers**, and **0% candidate coverage**. Precision remains
undefined because there are no candidates. These videos overlap training or
model-selection validation, not independent tests.

The six new videos were also sampled across their complete duration at 2 fps,
using the previously reviewed full-width spatial crop `y=[180,700)`. Automatic
timing returned `INCONCLUSIVE` on all six. With the previously selected time
intervals, recording **210351** produced `CANDIDATE_SINGLE_REMOVAL`, **THU iron**;
the other five were inconclusive. This candidate is **unverified**, because the
user has not provided that clip's actual outcome. Narrow assisted intervals can
also contain fewer than the required three samples per phase.

A separate diagnostic compares the four originally extracted JPEGs per phase
(not the 2-fps video samples):

| Recording | Manual JPEG-pair result |
| --- | --- |
| 210224 | NO_COUNT_CHANGE; did not identify the user-confirmed iron extraction |
| 210315 | Candidate SUN ibuprofen removal, unverified |
| 210351 | INCONCLUSIVE |
| 210505 | INCONCLUSIVE |
| 210556 | Candidate MON iron removal, unverified |
| 210644 | INCONCLUSIVE |

The differing JPEG/video results illustrate sampling/count instability, not
multiple verified successes. Five new clips were training data; clip 017 was
validation data. Only 210224's removed class (iron) is user-confirmed; no
six-video exact day/class accuracy is reported without complete human truth.
Neither thresholds nor class labels were changed to force successful outcomes.

All datasets, model checkpoints, logs, input hashes, and reports are local in
`backend_api/runs/official_blue_pm/corrected_batch_01/`:

- `data_audit.json`: replacement provenance, hashes, counts, and splits.
- `model_metrics.json`: selected checkpoints and validation metrics.
- `pills_model/weights/best.pt`: trained three-class detector.
- `compartments_model/weights/best.pt`: trained compartment segmenter.
- `original_four_video_evaluation.json`: scored original development clips.
- `six_full_video_evaluation.json`: full-duration new-video results with fixed
  spatial crop, automatic and assisted timing, no invented ground truth.
- `six_crop_pair_evaluation.json`: separate manual-JPEG diagnostic.
- `validation_count_evaluation.json`: exact count matches against annotations.

These strict-comparison results predate the target-scoped integration below.

## Target-medication comparison and API integration

The corrected-batch checkpoints are now used by `/dose-verification/analyze-video`.
The superseded two-row video algorithm, schedule-driven target selection,
automatic orientation calibration, and two-class crop classifier/trainer were
removed. The separate loose-pill photo detector and legacy orientation
preferences remain for their existing interfaces.

### What changed and measured results

Iron count fluctuations previously invalidated entire 21-count vectors.
Target mode compares each medication's **observed seven-day count vector**,
not independent per-cell majorities. It still requires at least three matching
samples and 75% agreement per phase. Stable competing target changes veto a
candidate; an unstable other medication does **not**, so the output explicitly
states that it is scoped evidence rather than whole-box verification.
Iron detection is retained, but target mode never claims an iron extraction.
Transfers preserve source/destination and report zero net pills removed.

Sampling at 4 fps with the same previously reviewed intervals and updated weights:

| Known development recording | Assisted result |
| --- | --- |
| 205200 | INCONCLUSIVE; Monday acetaminophen removal still missed |
| 205322 | Candidate Friday ibuprofen removal, matches reviewed outcome |
| 205454 | Candidate Wednesday -> Tuesday ibuprofen transfer, matches reviewed outcome |
| 205612 | Candidate Monday acetaminophen removal, matches reviewed outcome |

That is **3/4 exact events (75%)**, including **2/3 removals (66.7%)** and
**1/1 transfers**. Automatic phase selection remains **0/4**. These are four
development recordings exposed to training/model-selection and algorithm
development, not an independent test accuracy or an estimate of clinical
reliability. There are no no-removal negatives in this scored set. Agreement
scores are not calibrated correctness probabilities; adjacent/frozen frames
are correlated. Classification errors and changes in an unstable other class
can still produce misleading candidates. Every result requires review.

The primary remaining weakness is phase quality: moving/closed/occluded early
or late views, small overlapping pills, and inconsistent class counts.
The next useful improvement is independent-session data with clear stationary
phases and no-removal negatives, followed by validated phase/occlusion detection
and temporal object matching. Do not loosen thresholds to manufacture success.

The local initial report is
`backend_api/runs/official_blue_pm/target_class_evaluation_01.json`.
Reproduce with explicit comparison/fps and hashed model/case provenance:

```bash
.venv-vision/bin/python -m backend_api.scripts.training.evaluate_official_videos \
  --cases backend_api/runs/official_blue_pm/evaluation_cases.json \
  --pill-checkpoint backend_api/runs/official_blue_pm/corrected_batch_01/pills_model/weights/best.pt \
  --compartment-checkpoint backend_api/runs/official_blue_pm/corrected_batch_01/compartments_model/weights/best.pt \
  --comparison target --sample-fps 4 --device mps \
  --output backend_api/runs/official_blue_pm/target_class_evaluation_reproduced.json
```

Default CLI comparison remains `strict` at 2 fps to preserve historical
experiments. Use a fresh output path.

The six newer recordings were also rerun at 4 fps using full frames, exactly as
the API does (no fixed spatial crop):

| Recording | Automatic | Assisted |
| --- | --- | --- |
| 210224 | INCONCLUSIVE | INCONCLUSIVE |
| 210315 | Candidate SUN ibuprofen removal | Candidate SUN ibuprofen removal |
| 210351 | INCONCLUSIVE | NO_COUNT_CHANGE |
| 210505 | INCONCLUSIVE | INCONCLUSIVE |
| 210556 | INCONCLUSIVE | NO_COUNT_CHANGE |
| 210644 | INCONCLUSIVE | Candidate WED ibuprofen removal |

Those candidates are **unverified**, not additional correct events. Actual
outcomes are still unknown except the iron class for 210224, which target mode
does not claim to handle. Training/model-selection exposure and incomplete
truth prevent reporting accuracy on this batch. The report is
`backend_api/runs/official_blue_pm/target_six_full_frame_01.json`.

### Runtime contract

- Native defaults point to the local corrected-batch weights. Override with
  `OFFICIAL_PILL_CHECKPOINT`, `OFFICIAL_COMPARTMENT_CHECKPOINT`, and
  `OFFICIAL_VIDEO_DEVICE` (default `cpu`; local Apple testing used `mps`).
  Compose mounts `runs/` and provides explicit container paths. Weights remain
  separate local artifacts, not committed source. Missing/incompatible
  checkpoints return 503, never a fallback to old models.
- The runtime verifies three exact pill class names and a one-class
  **segmentation** checkpoint. Models are cached per path/device; restart after
  replacing files, preferably deploying immutable versioned artifact paths.
- Inference runs in a worker thread with one in-flight model call per process.
  Busy requests return 503 with `Retry-After`. Uploads are streamed with a
  50 MiB limit; API analysis rejects videos longer than 120 seconds. Research
  CLI duration remains unrestricted.
- Optional multipart timestamps are all-or-none, finite seconds in ordered,
  disjoint intervals inside the video. Choose stationary, unobstructed phases
  of roughly 1-2 seconds each. They select time only, not expected pills/days.
  The app offers these inputs; automatic timing currently performs poorly.
- Geometry is fixed SUN -> SAT, PM. No user schedule, selected compartment,
  or legacy orientation preference can change predictions. `wrong_slot`
  compares candidate evidence to the selected slot only after inference.
  PM compartment indices remain 7-13 for compatibility with existing records.
- Outcomes are `CANDIDATE_SINGLE_REMOVAL`, `CANDIDATE_TRANSFER`,
  `NO_COUNT_CHANGE`, or `INCONCLUSIVE`. **All require review**.
  `NO_COUNT_CHANGE` concerns targets only and does not establish no removal.
  `pre_count`/`post_count` are for the candidate class in its source cell.
- Inventory and adherence are never updated by this endpoint. Selected
  `medication_id` remains user metadata; `recognized_medication` is independent
  candidate evidence, not a confirmed medication identity.
- Each successful upload retains a sibling `.analysis.json` report containing
  frame evidence, selected times, scope, reason, and SHA-256 hashes of both
  models. History restores these fields without a schema migration. Preserve
  reports with their uploads; failed/rejected requests clean up partial files.
- The app labels candidates/transfers explicitly and never offers legacy
  orientation flipping for an official result.

### Integration validation

The real CPU model was exercised through the full FastAPI application using a
temporary in-memory database and isolated upload directory: reviewed clip 004
returned candidate MON acetaminophen removal, required review, left inventory
unchanged, and round-tripped the same evidence through history. The local
response is saved in `backend_api/runs/official_blue_pm/api_smoke_01.json`.
Automated API tests additionally check worker-thread execution, wrong-slot
metadata without inference steering, transfer semantics, no inventory/orientation
mutation, model-unavailable/busy errors, upload limits and cleanup.
