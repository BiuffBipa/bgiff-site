# BGIFF Website

Production-ready first-phase website for the Berlin Gate International Film Festival.

## Run locally

```bash
npm install
npm run dev -- -H 127.0.0.1
```

## Production build

```bash
npm run build
npm start -- -H 127.0.0.1
```

## Included

- Responsive festival homepage
- Festival, Submit, Awards, Programme and Journal sections
- Static film and editorial content models ready for a CMS
- Contact and German legal-page placeholders
- BGIFF brand assets, favicon and a corrected beam-free website hero
- SEO and Open Graph metadata

## Before public launch

1. Replace the FilmFreeway URL in `lib/data.ts` if the final festival slug differs.
2. Complete the legal identity and address in Impressum.
3. Have the final Privacy Policy and Terms reviewed for the actual providers used.
4. Connect the contact form to an email service.
5. Add a CMS once film, screening and editorial content begins.
6. Add cookie consent only if non-essential analytics or embeds are enabled.

## Brand asset note

The approved raster logo is preserved exactly as supplied. For large-format print and future vector animation, replace it with the final approved SVG master rather than auto-tracing the PNG.

## Platform (Phase A scaffold)

The festival management platform lives next to the site: `docs/platform/` (architecture, schema, build plan, decisions), `supabase/` (migrations, RLS, SQL tests), `lib/platform/` (domain code), `tests/`. Checks: `npm run lint && npm run typecheck && npm test && npm run db:check`. Nothing in the platform changes the public pages; all live switches are feature flags that default to off.
