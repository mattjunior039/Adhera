import { useState, type ReactNode } from 'react'
import { ArrowUpRight, EnvelopeSimple, Phone, Bell, CalendarBlank, Camera, Check, Clock, Cpu, LockKey, Pill, Scan, ShieldCheck, TextT, Users, Warning, WifiHigh, ArrowsClockwise, type Icon } from '@phosphor-icons/react'
import { AnimatePresence, motion, useIsPresent, useReducedMotion } from 'motion/react'
import { Reveal } from '../components/Reveal'
import { problem, howItWorks, privacy, comparison, story, team, contact, site } from '../content'
import './homepage.css'

const icons: Record<string, Icon> = { clock: Clock, pill: Pill, calendar: CalendarBlank, users: Users, scan: Scan, warning: Warning, refill: ArrowsClockwise, text: TextT, bell: Bell, shield: ShieldCheck }
const number = (index: number) => String(index + 1).padStart(2, '0')

function Section({ id, label, children, className = '' }: { id: string; label: string; children: ReactNode; className?: string }) {
  return <section id={id} className={`home-section ${className}`} aria-labelledby={`${id}-heading`}><div className="home-container"><div className="eyebrow">{label}</div>{children}</div></section>
}
function Heading({ id, children, sub }: { id: string; children: ReactNode; sub?: string }) {
  return <Reveal><h2 id={`${id}-heading`} className="section-heading">{children}</h2>{sub && <p className="section-intro">{sub}</p>}</Reveal>
}
function Tray({ detected = false }: { detected?: boolean }) {
  return <div className={`diagram-tray ${detected ? 'is-detected' : ''}`} aria-hidden="true"><div className="tray-days">{['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day, i) => <span key={i}>{day}</span>)}</div>{['AM', 'PM'].map((time, row) => <div className={`tray-row row-${row}`} key={time}>{Array.from({ length: 7 }, (_, i) => <span className={`tray-cell ${detected && i === 2 && row === 0 ? 'selected-cell' : ''}`} key={i}>{detected && i === 2 && row === 0 ? <Check size={18} /> : <i />}</span>)}<b>{time}</b></div>)}</div>
}
function WorkflowStepCopy({ step }: { step: (typeof howItWorks.steps)[number] }) {
  const isPresent = useIsPresent()
  const reduceMotion = useReducedMotion()
  const transition = { duration: reduceMotion ? 0 : 0.24, ease: [0.22, 1, 0.36, 1] as const }

  return <motion.div className="workflow-step-copy" id={`workflow-step-detail-${step.key}`} role="region" aria-labelledby={`workflow-title-${step.key}`} aria-hidden={!isPresent} inert={!isPresent} initial={{ opacity: 0, height: 0, y: reduceMotion ? 0 : -4 }} animate={{ opacity: 1, height: 'auto', y: 0 }} exit={{ opacity: 0, height: 0, y: reduceMotion ? 0 : -4 }} transition={transition}><p>{step.body}</p></motion.div>
}

export function Problem() {
  return <Section id="problem" label="The everyday problem">
    <div className="problem-top"><Heading id="problem">{problem.heading}</Heading><div className="problem-stat"><strong>{problem.stat.value}</strong><p>{problem.stat.caption}</p><a href={problem.source.href} target="_blank" rel="noreferrer">{problem.source.label}<ArrowUpRight size={14} /></a></div></div>
    <div className="problem-reasons">{problem.cards.map((item) => { const Glyph = icons[item.icon]; return <article key={item.title}><Glyph size={28} weight="light" /><h3>{item.title}</h3><p>{item.body}</p></article> })}</div>
  </Section>
}

export function HowItWorks() {
  const [active, setActive] = useState(0)
  const reduceMotion = useReducedMotion()
  const stepIcons = [Scan, CalendarBlank, Camera, Check, Bell]
  const ActiveIcon = stepIcons[active]
  const activeStep = howItWorks.steps[active]
  const transition = { duration: reduceMotion ? 0 : 0.24, ease: [0.22, 1, 0.36, 1] as const }
  const labelTransition = { duration: reduceMotion ? 0 : 0.16, ease: [0.22, 1, 0.36, 1] as const }

  return <Section id="how-it-works" label="How it works">
    <Heading id="how-it-works">{howItWorks.heading}</Heading>
    <div className="workflow-layout">
      <div className="workflow-steps">
        {howItWorks.steps.map((step, i) => <div className={`workflow-step ${i === active ? 'active' : ''}`} key={step.key}>
          <h3><button type="button" id={`workflow-title-${step.key}`} aria-expanded={i === active} onClick={() => setActive(i)}>
            <span className="workflow-index">{number(i)}</span><span className="workflow-title">{step.title}</span><span className="step-symbol" aria-hidden="true"><span className={i !== active ? 'is-visible' : ''}>+</span><span className={i === active ? 'is-visible' : ''}>−</span></span>
          </button></h3>
          <AnimatePresence initial={false} mode="wait">
            {i === active && <WorkflowStepCopy step={step} key={step.key} />}
          </AnimatePresence>
        </div>)}
      </div>
      <div className="workflow-visual" role="img" aria-label={`Illustrative ${activeStep.label.toLowerCase()} diagram`}>
        <div className="visual-meta">
          <AnimatePresence initial={false} mode="wait">
            <motion.div className="visual-meta-state" key={activeStep.key} initial={{ opacity: 0, y: reduceMotion ? 0 : 3 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: reduceMotion ? 0 : -3 }} transition={labelTransition}>
              <span>ADHERA / {activeStep.label.toUpperCase()}</span><span>{number(active)} / 05</span>
            </motion.div>
          </AnimatePresence>
        </div>
        <div className="workflow-art">
          <AnimatePresence initial={false} mode="wait">
            <motion.div className="workflow-art-state" key={activeStep.key} initial={{ opacity: 0, y: reduceMotion ? 0 : 5 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: reduceMotion ? 0 : -5 }} transition={transition}>
              {active === 0 ? <div className="scan-sheet"><Scan size={36} weight="light" /><span>Prescription</span><div className="scan-line" /><div className="scan-line short" /><div className="scan-line" /><div className="scan-line short" /><div className="scan-beam" /></div> : active === 4 ? <div className="notification-demo"><span className="notification-icon"><Bell size={28} weight="light" /></span><strong>{activeStep.title}</strong><div className="notification-people"><span>Patient</span><span>Caregiver</span></div></div> : <><div className="sensor-symbol"><ActiveIcon size={34} weight="light" /></div><div className="signal-line" /><Tray detected={active === 3} /></>}
            </motion.div>
          </AnimatePresence>
        </div>
        <div className="visual-caption"><ActiveIcon size={18} /><AnimatePresence initial={false} mode="wait"><motion.span key={activeStep.key} initial={{ opacity: 0, y: reduceMotion ? 0 : 3 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: reduceMotion ? 0 : -3 }} transition={labelTransition}>{activeStep.label}</motion.span></AnimatePresence><span>Illustrative view</span></div>
      </div>
    </div>
  </Section>
}



export function Privacy() {
  const flowIcons = [Camera, WifiHigh, Cpu, Users]
  return <Section id="privacy" label="Privacy" className="privacy-section"><div className="privacy-heading"><Heading id="privacy" sub={privacy.sub}>{privacy.heading}</Heading><div className="privacy-seal"><LockKey size={72} weight="thin" aria-hidden="true" /><span>Local by design</span></div></div>
    <div className="privacy-boundary"><div className="privacy-flow">{privacy.flow.map((item, i) => { const Glyph = flowIcons[i]; return <div className="privacy-node" key={item.key}><div className="flow-symbol"><Glyph size={30} weight="light" /></div><span className="mono">{number(i)}</span><h3>{item.label}</h3><p>{item.detail}</p>{i < 3 && <span className="flow-connector" aria-hidden="true">→</span>}</div> })}</div></div>
    <ul className="privacy-promises">{privacy.contrast.map(text => <li key={text}><Check size={18} /><span>{text}</span></li>)}</ul>
  </Section>
}

export function Comparison() {
  return <Section id="comparison" label="The Adhera approach"><Heading id="comparison">{comparison.heading}</Heading><p className="table-hint">Compare approaches <span aria-hidden="true">↔</span></p><div className="comparison-scroll" role="region" aria-label="Product comparison, scroll horizontally on smaller screens" tabIndex={0}><table className="comparison-table"><caption className="sr-only">{comparison.heading}</caption><thead><tr><th scope="col">At a glance</th>{comparison.columns.map((column, i) => <th className={i === 2 ? 'adhera-column' : ''} scope="col" key={column}>{i === 2 && <span className="brand-dot" />}{column}</th>)}</tr></thead><tbody>{comparison.rows.map(row => <tr key={row.label}><th scope="row">{row.label}</th>{row.values.map((value, i) => <td className={i === 2 ? 'adhera-column' : ''} key={i}>{value}</td>)}</tr>)}</tbody></table></div></Section>
}



export function Story() {
  return <Section id="story" label="Our story" className="story-section"><div className="story-layout"><div><Heading id="story">{story.heading}</Heading><div className="story-mark" aria-hidden="true"><span /><span /></div></div><div className="story-prose">{story.paragraphs.map((paragraph, i) => <p className={i === 2 ? 'story-conclusion' : ''} key={paragraph}>{paragraph}</p>)}</div></div></Section>
}

export function Team() {
  return <Section id="team" label="People"><Heading id="team">{team.heading}</Heading><div className="team-grid">{team.members.map((member, i) => <article key={i}><div className="team-portrait">{member.photo ? <img src={`${import.meta.env.BASE_URL}${member.photo}`} alt={member.name} loading="lazy" /> : <><Users size={46} weight="thin" /><span>Photo placeholder / {number(i)}</span></>}</div><h3>{member.name}</h3><p>{member.role}</p></article>)}</div><div className="team-context"><p>{team.collective}</p><small>{team.disclaimer}</small></div></Section>
}


export function Contact() {
  return <Section id="contact" label="Community & Contact" className="contact-section"><div className="contact-layout"><Heading id="contact" sub={contact.sub}>{contact.heading}</Heading><div><div className="contact-methods"><a href="mailto:matthew.flowerhill@gmail.com" className="contact-method"><EnvelopeSimple size={32} weight="light" /><div><span className="contact-method-label">Email</span><span className="contact-method-value">matthew.flowerhill@gmail.com</span></div></a><a href="tel:6084485111" className="contact-method"><Phone size={32} weight="light" /><div><span className="contact-method-label">Phone</span><span className="contact-method-value">(608) 448-5111</span></div></a></div></div></div></Section>
}

export function Footer() {
  return <footer className="site-footer"><div className="home-container"><div className="footer-top"><a className="footer-brand" href="#product" aria-label="Adhera, back to top"><span className="brand-symbol"><img src={`${import.meta.env.BASE_URL}brand/adhera-logo.png`} alt="" /></span><span className="brand-name"><img src={`${import.meta.env.BASE_URL}brand/adhera-logo.png`} alt="" /></span></a><nav aria-label="Footer">{site.nav.map(link => <a href={link.href} key={link.href}>{link.label}</a>)}<a href="#privacy">Privacy</a><a href="#contact">Contact</a></nav></div><div className="footer-logo" aria-hidden="true"><img src={`${import.meta.env.BASE_URL}brand/adhera-logo.png`} alt="" /></div><div className="footer-bottom"><span>© {new Date().getFullYear()} {site.name}</span><span>Medication adherence, verified.</span><a href="#product">Back to top ↑</a></div></div></footer>
}
