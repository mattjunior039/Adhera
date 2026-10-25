import { Nav } from './components/Nav'
import { Hero } from './sections/Hero'
import { Introducing } from './sections/Introducing'
import { Problem, HowItWorks, Privacy, Comparison, Story, Team, Contact, Footer } from './sections/Homepage'

export default function App() {
  return (
    <>
      <a className="skip-link" href="#main-content">Skip to content</a>
      <Nav />
      <main id="main-content" tabIndex={-1}>
        <Hero />
        <Problem />
        <Introducing />
        <HowItWorks />

        <Privacy />
        <Comparison />
        <Story />
        <Team />
        <Contact />
      </main>
      <Footer />
    </>
  )
}
