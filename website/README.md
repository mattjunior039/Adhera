# Adhera Website

The public project website for Adhera: the problem, how the smart pillbox and
app work, privacy, the team, and contact details. It is published with GitHub
Pages at **<https://mattjunior039.github.io/PillBox/>**.

Built with React 19, TypeScript, Vite, Tailwind CSS, Motion, and
React Three Fiber (Three.js) for the interactive 3D pillbox model.

## Run locally

Requires Node.js 20.19+ or 22.12+.

```bash
cd website
npm install
npm run dev        # http://localhost:5173/PillBox/
```

Other commands: `npm run build` (type-check and production build into `dist/`),
`npm run preview` (serve the build), and `npm run lint` (oxlint).

## Where things are

| Path | Contents |
| --- | --- |
| `src/content.ts` | All page copy, navigation, and team details. Edit text here. |
| `src/sections/` | Page sections (hero, introduction, problem, how it works, privacy, comparison, story, team, contact) |
| `src/components/` | Navigation, buttons, and layout helpers |
| `src/three/` | 3D scenes for the pillbox model |
| `public/models/` | Open and closed pillbox models (`.glb`) |
| `public/brand/`, `public/team-*.jpg` | Logo and team photos |

## Deployment

`.github/workflows/website.yml` builds and deploys the site whenever
`website/` changes on `main`. To enable it the first time, go to the
repository's **Settings → Pages** and set **Source** to **GitHub Actions**.

The site is served from `/<repository-name>/`. The workflow sets this
automatically; for local builds the default is `/PillBox/`, and you can
override it with `BASE_PATH=/ npm run build`.
