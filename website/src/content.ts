const repoUrl = 'https://github.com/mattjunior039/PillBox'

export const site = {
  name: 'Adhera',
  repoUrl,
  contactEmail: 'matthew.flowerhill@gmail.com',
  nav: [
    { label: 'Product', href: '#product' },
    { label: 'How it works', href: '#how-it-works' },
    { label: 'Our story', href: '#story' },
    { label: 'Team', href: '#team' },
    { label: 'Source code', href: repoUrl },
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
      body: 'Photograph the pharmacy bottle. Text recognition runs on the phone and reads the drug name, dose, frequency, and instructions.',
    },
    {
      key: 'schedule',
      label: 'Schedule',
      title: 'Build the regimen',
      body: 'Adhera checks the drug name against the NIH RxNorm database and turns the label instructions into a weekly schedule.',
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
    'Only drug names, never images, are checked against NIH RxNorm',
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
    { name: 'Matthew Flowerhill', role: 'Software and AI Engineer', photo: 'team-matthew.jpg' },
    { name: 'Neil Gupta', role: 'Hardware & IoT Integration', photo: 'team-neil.jpg' },
    { name: 'Ved Gandhi', role: 'Product Manager', photo: 'team-ved.jpg' },
  ],
  collective:
    'Our team brings experience across healthcare, machine learning, software development, and medical-data environments, including work with organizations such as Kaiser Permanente, Cedars-Sinai, UC Davis Health, and Dartmouth Geisel School of Medicine.',
  disclaimer: 'These organizations are listed to describe team members\u2019 prior experience and do not endorse Adhera.',
}

export const contact = {
  heading: 'Working with the community to help us improve medication adherence.',
  sub: 'We are looking to collaborate with pharmacists, healthcare professionals, researchers, and organizations interested in evaluating Adhera.',
  partnershipCta: { label: 'Discuss a partnership' },
}
