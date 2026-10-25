export const site = {
  name: 'Adhera',
  contactEmail: 'matthew.flowerhill@gmail.com',
  nav: [
    { label: 'Product', href: '#product' },
    { label: 'How it works', href: '#how-it-works' },
    { label: 'Our story', href: '#story' },
    { label: 'Team', href: '#team' },
  ],
  primaryCta: { label: 'Contact the team', href: '#contact' },
  secondaryCta: { label: 'See how it works', href: '#how-it-works' },
}

export const hero = {
  headline: 'Medication adherence, verified.',
  sub: 'A smart pill organizer that confirms the right dose was taken at the right time, without the cost or complexity of a robotic dispenser.',
}

export const problem = {
  heading: 'Taking medication correctly is harder than it looks.',
  lede: 'Around half of people with chronic conditions do not take their medication as prescribed. The reasons are ordinary, and they compound.',
  source: {
    label: 'World Health Organization, Adherence to Long-Term Therapies (2003)',
    href: 'https://iris.who.int/handle/10665/42682',
  },
  stat: { value: '~50%', caption: 'of patients with chronic conditions do not take medication as prescribed' },
  cards: [
    {
      icon: 'clock',
      title: 'Missed doses',
      body: 'A morning dose slips by. Nobody notices until the next one, or the one after that.',
    },
    {
      icon: 'pill',
      title: 'The wrong pill',
      body: 'Similar tablets, a full weekly tray, and one mistake that looks exactly like a correct dose.',
    },
    {
      icon: 'calendar',
      title: 'Complicated schedules',
      body: 'Four prescriptions, three frequencies, and label instructions printed in six-point type.',
    },
    {
      icon: 'users',
      title: 'Caregivers left guessing',
      body: 'Family members want to help but cannot see what happened unless they are in the room.',
    },
  ],
  personal: {
    quote:
      'We watched our grandmother manage a weekly organizer on her own. Some days we simply did not know whether she had taken her medication.',
    attribution: 'Adhera founding team',
  },
}

export const introducing = {
  heading: 'Meet Adhera.',
  body: 'Adhera pairs a familiar weekly pill organizer with a small inward-facing camera and a software platform that understands the prescription. When the lid closes, Adhera checks what was removed against what was scheduled, and tells the right person when something is off.',
  positioning:
    'Designed to reduce hardware complexity and cost compared with robotic dispensers, while adding the one thing organizers never had: verification.',
  parts: [
    {
      title: 'Smart pill organizer',
      body: 'Fourteen compartments, AM and PM, with a lid-mounted camera that only ever looks at the pills.',
    },
    {
      title: 'Software platform',
      body: 'Prescription scanning, scheduling, dose verification, and caregiver alerts in one app.',
    },
  ],
}

export const howItWorks = {
  heading: 'From prescription label to verified dose.',
  steps: [
    {
      key: 'prescription',
      label: 'Prescription',
      title: 'Scan the label',
      body: 'Photograph the pharmacy bottle. OCR reads the drug name, dose, frequency, and instructions.',
    },
    {
      key: 'schedule',
      label: 'Schedule',
      title: 'Build the regimen',
      body: 'Adhera normalizes the drug name and turns label instructions into a weekly schedule.',
    },
    {
      key: 'detection',
      label: 'Detection',
      title: 'Sense the lid',
      body: 'A magnetic sensor wakes the camera only when the lid opens and closes. No continuous recording.',
    },
    {
      key: 'verification',
      label: 'Verification',
      title: 'Check the compartment',
      body: 'Computer vision compares before and after frames to see which compartment changed and how many pills left.',
    },
    {
      key: 'alert',
      label: 'Alert',
      title: 'Notify when it matters',
      body: 'Wrong day, wrong time, a partial dose, or a completely missed medication. The patient and caregiver hear about it.',
    },
  ],
}

export const features = {
  heading: 'Eight capabilities. One quiet device.',
  items: [
    {
      key: 'cv',
      icon: 'eye',
      title: 'Edge computer vision',
      body: 'A custom YOLOv8 model determines which compartment was opened and whether the dose was removed.',
      metric: { value: '96.3%', label: 'mAP50 on pill detection' },
    },
    {
      key: 'ocr',
      icon: 'scan',
      title: 'On-device OCR',
      body: 'Reads prescription labels, including curved bottles, and extracts the fields that matter.',
    },
    {
      key: 'schedule',
      icon: 'calendar',
      title: 'Medication scheduling',
      body: 'Converts label instructions into AM and PM compartments across the week.',
    },
    {
      key: 'misuse',
      icon: 'warning',
      title: 'Misuse detection',
      body: 'Flags pills taken from the wrong day or time slot, and doses that were only partly taken.',
    },
    {
      key: 'refill',
      icon: 'refill',
      title: 'Refill prediction',
      body: 'Tracks consumption against the filled quantity and projects when a refill is due.',
    },
    {
      key: 'accessible',
      icon: 'text',
      title: 'Accessible instructions',
      body: 'Rewrites dense label warnings as large-print, high-contrast guidance you can print.',
    },
    {
      key: 'caregiver',
      icon: 'bell',
      title: 'Caregiver alerts',
      body: 'Missed, early, or incorrect doses reach a family member or clinician you choose.',
    },
    {
      key: 'privacy',
      icon: 'shield',
      title: 'Privacy-first architecture',
      body: 'Images are processed on your local network instead of being routinely sent to cloud servers.',
    },
  ],
}

export const explorer = {
  heading: 'Take it apart.',
  sub: 'Drag to rotate. Scroll or pinch to zoom. Select a point to see what it does.',
  hotspots: [
    {
      id: 'camera',
      title: 'Inward-facing camera',
      body: 'An ESP32-CAM module under the lid. It faces the tray, never the room or the person.',
    },
    {
      id: 'compartments',
      title: 'Fourteen compartments',
      body: 'Seven days, AM and PM. Color-coded rows help the vision model orient the tray in any direction.',
    },
    {
      id: 'processor',
      title: 'Local compute',
      body: 'Frames are handled on the device and your home network, then matched against the schedule.',
    },
    {
      id: 'lights',
      title: 'Indicator lights',
      body: 'A glanceable status: dose due, dose confirmed, or something needs attention.',
    },
    {
      id: 'lid',
      title: 'Hall-effect lid sensor',
      body: 'A magnet and sensor detect when the lid opens and closes, so the camera sleeps the rest of the time.',
    },
    {
      id: 'power',
      title: 'USB-C power',
      body: 'Low standby draw because the camera only wakes on a lid event.',
    },
  ],
}

export const privacy = {
  heading: 'Designed around local processing.',
  sub: 'Adhera is built to minimize exposure of sensitive medication data. Images stay on your home network for processing.',
  flow: [
    { key: 'device', label: 'Adhera organizer', detail: 'Captures two still frames on lid close' },
    { key: 'wifi', label: 'Local Wi-Fi', detail: 'Direct transfer over mDNS, adhera.local' },
    { key: 'compute', label: 'Local processing', detail: 'Vision model and schedule logic' },
    { key: 'people', label: 'Patient and caregiver', detail: 'Only the outcome is shared' },
  ],
  contrast: [
    'No medication images sent for external cloud processing',
    'Camera faces the pills, not the room',
    'Wakes on a lid event, no continuous video',
  ],
}

export const comparison = {
  heading: 'A different job from a dispenser.',
  columns: ['Traditional organizer', 'Robotic dispenser', 'Adhera'],
  rows: [
    { label: 'Core function', values: ['Organizes pills', 'Dispenses automatically', 'Verifies medication use'] },
    { label: 'Intelligence', values: ['None', 'Complex hardware', 'Smart software, simple hardware'] },
    { label: 'Misuse detection', values: ['None', 'Limited', 'Wrong slot, wrong time, partial dose'] },
    { label: 'Hardware', values: ['Minimal', 'Motors and mechanisms', 'Designed to reduce complexity and cost'] },
    { label: 'Caregiver visibility', values: ['Limited', 'Connected ecosystem', 'Privacy-focused monitoring'] },
  ],
}

export const prototype = {
  heading: 'Built, not just imagined.',
  sub: 'Adhera started as a working prototype called PillBox. These are from the bench.',
  media: [
    { src: '', title: 'Hardware prototype', caption: '3D-printed 7 by 2 organizer with lid camera', span: 'wide' },
    { src: '', title: 'Computer vision output', caption: 'Compartment isolation and pill detection', span: 'tall' },
    { src: '', title: 'OCR processing', caption: 'Label unwarping and field extraction', span: 'normal' },
    { src: '', title: 'Mobile app', caption: 'Schedule and dose verification screens', span: 'normal' },
    { src: '', title: 'Testing', caption: 'Video verification trials', span: 'normal' },
  ],
  stats: [
    { value: '672', label: 'annotated compartment images' },
    { value: '96.3%', label: 'mAP50 detection accuracy' },
    { value: '14', label: 'compartments tracked per frame' },
  ],
}

export const architecture = {
  heading: 'System architecture.',
  sub: 'Three layers, each replaceable. Proprietary details omitted.',
  layers: [
    {
      key: 'hardware',
      label: 'Hardware',
      items: ['ESP32-CAM lid camera', 'Hall-effect lid sensor', '7 by 2 pill organizer', 'Local compute device'],
    },
    {
      key: 'intelligence',
      label: 'Intelligence',
      items: ['YOLOv8 pill detection', 'Label OCR and unwarping', 'Drug name normalization', 'Schedule and misuse logic'],
    },
    {
      key: 'software',
      label: 'Software',
      items: ['Patient app', 'Caregiver dashboard', 'Notifications', 'Refill tracking'],
    },
  ],
}

export const story = {
  heading: 'Adhera addresses a widespread problem.',
  paragraphs: [
    'Many families rely on a weekly medication organizer kept on the kitchen counter. It is a good system until it isn’t. A compartment might still be full at dinner, or empty a day early, leaving everyone uncertain about what actually happened.',
    'This uncertainty is shared by families everywhere. Traditionally, the options have been a basic plastic box that knows nothing, or a complex robotic dispenser that costs more and does more than most people need.',
    'Adhera was built as the middle ground: keeping the familiar organizer people already understand, while adding just enough intelligence to confirm the dose.',
  ],
}

export const team = {
  heading: 'The team.',
  members: [
    { name: 'Matthew Flowerhill', role: 'Software and AI Engineer', photo: 'team-matthew.png' },
    { name: 'Neil Gupta', role: 'Hardware & IoT Integration', photo: 'team-neil.png' },
    { name: 'Ved Gandhi', role: 'Product Manager', photo: 'team-ved.png' },
  ],
  collective:
    'Our team brings experience across healthcare, machine learning, software development, and medical-data environments, including work with organizations such as Kaiser Permanente, Cedars-Sinai, UC Davis Health, and Dartmouth Geisel School of Medicine.',
  disclaimer: 'These organizations are listed to describe team members\u2019 prior experience and do not endorse Adhera.',
}

export const progress = {
  heading: 'Where we are.',
  milestones: [
    { title: 'Identified the adherence problem', status: 'done' },
    { title: 'Conducted community interviews', status: 'done' },
    { title: 'Built software prototype', status: 'done' },
    { title: 'Developed OCR pipeline', status: 'done' },
    { title: 'Implemented computer vision detection', status: 'done' },
    { title: 'Built initial hardware prototype', status: 'done' },
    { title: 'Began pharmacy and healthcare outreach', status: 'active' },
    { title: 'Testing phase', status: 'active' },
  ],
}

export const community = {
  heading: 'Working with the community.',
  sub: 'We are early and looking for people who can pressure-test Adhera in the real world.',
  groups: ['Pharmacists', 'Physicians', 'Healthcare advisors', 'Technical mentors', 'Pilot organizations'],
}

export const contact = {
  heading: 'Working with the community to help us improve medication adherence.',
  sub: 'We are looking to collaborate with pharmacists, healthcare professionals, researchers, and organizations interested in evaluating Adhera.',
  partnershipCta: { label: 'Discuss a partnership' },
}
