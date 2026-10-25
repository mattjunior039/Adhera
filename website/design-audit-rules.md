# UI/UX & Motion Audit Guidelines

Act as a world-class Design Engineer. Audit and rewrite the code based on the following three frameworks:

## 1. Taste-Skill (Anti-Slop Framework)
* **No Generic AI UI:** Eliminate centered, bootstrap-looking layouts, generic cards with heavy drop shadows, and unnecessary borders.
* **Layout & Spacing:** Rely on negative space and alignment to separate content, not physical lines. Use asymmetric or modern bento grids where appropriate.
* **Typography:** Ban harsh elements. Use premium font pairings. Enforce strict em-dash rules and ensure the hierarchy is immediately obvious without reading.

## 2. UI-UX Pro Max (Design Intelligence)
* **Aesthetics:** strictly AVOID "AI purple/pink gradients", neon colors, harsh dark modes, and emojis as icons (use SVGs like Lucide/Heroicons). 
* **Resilient UI:** Essential text, chips, and badges must wrap gracefully without clipping at narrow widths or browser zooms. Badges cannot rely on color alone for meaning.
* **Accessibility:** Ensure a minimum 4.5:1 text contrast. All interactive elements must have `cursor-pointer` and visible focus states for keyboard navigation.

## 3. Design Motion Principles
* **Anti-Slop Checklist:** aggressively remove pulsing indicators, uniform fade-ins, "hover-scale-on-everything", stagger-spam, and bouncy springs on utility actions.
* **Motion Gaps:** Find conditional UI that should animate but doesn't (e.g., missing enter/exit transitions on modals, instant state swaps).
* **The Lenses:** 
  - *Restraint:* "Should this animate at all?" Apply to high-frequency actions.
  - *Polish:* "Is this subtle enough?" Use gentle opacities and transforms, respecting `prefers-reduced-motion`.