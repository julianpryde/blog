# Implementation Plan: POSSE Blog (HTTPS + Gemini)

## Goal

Build a personal blog about secure software development. It is served identically over HTTPS and Gemini, is fully static, and is built and deployed by one script run from the local repo. Posts are published on my own domain first and syndicated elsewhere by link (POSSE).

## Constraints

- **No dynamic pages.** HTTPS output is plain static HTML and CSS. No JavaScript is required to read the site.
- **Feature parity.** Every page exists in both protocols with the same content and links. If gemtext can't express something, the HTML version doesn't get it either.
- **Minimal build.** Use the Python 3 standard library only: no pip dependencies, no static site generator framework, no Node toolchain for the build. `wrangler` is used only for deployment.
- **Low cost.** Target $0/month using the Cloudflare free plan and the GCP Always Free e2-micro.
- **Secure by default.** This is a security blog, so the infrastructure should reflect that (details under Security Requirements).

## Architecture

```
repo (gemtext source)
   └── build.py ──┬── dist/html/   ── wrangler deploy ──► Cloudflare Workers static assets ──► https://example.com
                  └── dist/gemini/ ── rsync over SSH ───► GCP e2-micro (us-west1) + Agate ──► gemini://gemini.example.com
```

- **Source of truth:** gemtext (`.gmi`) files in `content/`. Gemtext converts to HTML without loss; the reverse direction loses information.
- **HTTPS:** Cloudflare Workers with static assets only. No Worker script, no `run_worker_first`.
- **Gemini:** [Agate](https://github.com/mbrubeck/agate) on a GCP e2-micro in `us-west1`, standard persistent disk (30 GB or less), Standard network tier.
- **DNS (Cloudflare):**
  - `example.com`: proxied (orange cloud) to the Worker.
  - `gemini.example.com`: an A record set to DNS only (grey cloud), pointing at the VM's static IP. It must not be proxied, because Cloudflare does not carry traffic on port 1965.
- **Infrastructure as code:** Terraform for the GCP VM, firewall, static IP, and the Cloudflare DNS records.

## Repository Layout

```
content/
  index.gmi                # homepage (hand-written; post list injected at build)
  about.gmi
  posts/
    YYYY-MM-DD-slug.gmi
templates/
  page.html                # single HTML shell with {{title}}, {{body}}, {{canonical_gemini}}
static/
  style.css                # small, no web fonts, respects prefers-color-scheme
build.py
deploy.sh                  # or a `deploy` subcommand of build.py
wrangler.jsonc
infra/
  main.tf  variables.tf  outputs.tf
  cloud-init.yaml          # installs and configures Agate
syndicate.py               # POSSE step (phase 5)
README.md
```

## Content Conventions

- **Post metadata:** keep it in-band so the file stays valid gemtext.
  - Line 1 is `# Title`.
  - Line 2 is an optional date line in the form `Published: YYYY-MM-DD`.
  - The date and slug come from the filename. Do not use YAML front matter.
- **Links:** write internal links as relative paths ending in `.gmi`. The HTML build rewrites them to `.html`, or to clean URLs if that proves simple.
- **Images:** avoid them in v1. If one is needed, link to it (`=> image.png Alt text`) instead of embedding it inline. This keeps the two versions identical.

## build.py Requirements

1. Walk `content/` and parse each `.gmi` file.
2. Copy gemtext unchanged into `dist/gemini/`, except the index, which gets the generated post list injected.
3. Convert each file to HTML using a small hand-written gemtext parser that covers the full spec:
   - text lines become `<p>`
   - `=>` links become `<p><a>` (rewrite internal `.gmi` links)
   - `#`, `##`, and `###` headings become `<h1>`–`<h3>`
   - `*` list items become consecutive `<ul><li>` elements
   - `>` quote lines become `<blockquote>`
   - preformatted blocks become `<pre>`, with the alt text as `aria-label`
   - all text is HTML-escaped
4. Generate the post index for both outputs.
5. Generate an Atom feed for each protocol (`dist/html/atom.xml` and `dist/gemini/atom.xml`) using absolute URLs for that protocol.
6. Each HTML page includes:
   - `<link rel="canonical">` pointing at its own HTTPS URL
   - a visible link to the Gemini version
   - `<link rel="alternate" type="application/atom+xml">`
7. Write `dist/html/_headers` with the security headers listed below.
8. Make the build deterministic: sort all file walks, and avoid timestamps other than post dates.
9. Support `--check`, which builds and validates without deploying. It must:
   - fail on broken internal links
   - fail on posts missing a title
   - fail on duplicate slugs
10. Write unit tests for the gemtext-to-HTML converter using `unittest` from the standard library.

## Deploy

`deploy.sh` does the following, in order:

1. Run `python3 build.py --check`, then `python3 build.py`.
2. Run `npx wrangler deploy` with an assets-only configuration in `wrangler.jsonc`:
   - `assets.directory = "./dist/html"`
   - `not_found_handling = "404-page"`
3. Run `rsync -az --delete dist/gemini/ deploy@gemini.example.com:/srv/gemini/` using a dedicated SSH key that is restricted to rsync.
4. Exit non-zero on any failure, and do not partially deploy one protocol if the build failed.

## Infrastructure (Terraform + cloud-init)

**GCP**

- Create an `e2-micro` VM in `us-west1-b` running Debian stable, with a 30 GB standard persistent disk and the Standard network tier.
- Reserve a static external IP.
- Use a dedicated service account with no scopes (the VM needs no GCP API access).
- Firewall rules:
  - allow TCP 1965 from `0.0.0.0/0`
  - allow TCP 22 only from my IP (or use IAP TCP forwarding instead)
  - deny all other ingress
- Enable OS Login and disable password authentication.

**cloud-init**

- Create an unprivileged `agate` system user that owns `/srv/gemini`, which is read-only to the service.
- Install the Agate release binary and verify its checksum.
- Run Agate as a hardened systemd unit with:
  - `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`
  - `AmbientCapabilities` not needed, because 1965 is not a privileged port
- Agate auto-generates its TLS certificate (TOFU, the Gemini norm). Store the key under `/var/lib/agate` and never regenerate it on redeploy, since visitors pin the certificate.
- Enable unattended-upgrades.
- Create a `deploy` user whose `authorized_keys` entry is restricted with `command=` or `rrsync` so it can only write to `/srv/gemini`.

**Cloudflare**

- Terraform the two DNS records.
- Enable "Always Use HTTPS", HSTS, and a TLS 1.2 minimum.

## Security Requirements

**HTTP headers** (via `_headers`):

- `Content-Security-Policy: default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: no-referrer`
- `Permissions-Policy` with everything disabled

**Supply chain and secrets**

- Pin the wrangler version.
- Pin the Agate version and verify its checksum.
- Keep secrets out of the repo: use a Cloudflare API token scoped to Workers and DNS for this zone, and a GCP credential scoped to the project.
- Add `SECURITY.md` and `/.well-known/security.txt`.

## POSSE (Phase 5)

`syndicate.py` does the following:

1. Detect posts that are newly published since the last recorded run, tracked in `syndication.json` in the repo.
2. For each new post, post the title, a one-line summary, and the canonical HTTPS URL to configured targets. Start with Mastodon via its REST API, with the token taken from an environment variable.
3. Record the returned syndication URLs in `syndication.json`.
4. On the next build, render those URLs on the post page as "Also posted on: …" links, in both protocols.

Rules:

- Syndication is a separate command, never an automatic side effect of `deploy`.
- It is idempotent: re-running it never double-posts.

## Phases and Acceptance Criteria

1. **Build.** `build.py` plus tests; `dist/` output passes `--check`; HTML validates; every `.gmi` file has an HTML twin.
2. **HTTPS deploy.** Site is live on a `workers.dev` URL, then on the custom domain. Headers are verified with `curl -I`.
3. **Infrastructure.** Terraform applies cleanly. `gemini://gemini.example.com/` loads in a Gemini client (e.g. Lagrange or `amfora`). Port 22 is not reachable from other IPs.
4. **One-command deploy.** `./deploy.sh` publishes both protocols, and a changed post appears in both.
5. **POSSE.** A test post syndicates to Mastodon once, and the backlink renders.

## Out of Scope for v1

Comments, analytics, search, JavaScript, images inline in body text, CI/CD (deploys run locally for now), and syndication targets beyond Mastodon.

## Open Items for Me (Julian) to Supply

- Domain name
- Syndication accounts
- My SSH public key and admin IP
- The GCP project ID
