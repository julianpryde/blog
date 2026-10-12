# Surfaced

A static blog about secure software development, served identically at https://surfaced.run/ and gemini://gemini.surfaced.run/. See `PLAN.md` for the design.

## Layout

| Path | Purpose |
| --- | --- |
| `content/` | Gemtext source. `index.gmi`, `about.gmi`, `posts/YYYY-MM-DD-slug.gmi` |
| `templates/page.html` | HTML shell. Placeholders: `{{title}}`, `{{body}}`, `{{canonical_https}}`, `{{canonical_gemini}}` |
| `static/` | Copied into the output. `style.css` and `_headers` go to HTML only; `.well-known/` goes to both |
| `wrangler.jsonc`, `package.json` | Assets-only Worker for the HTTPS site, wrangler pinned |
| `infra/` | Terraform for the GCP VM, firewall, static IP and Cloudflare DNS/zone settings; `cloud-init.yaml` sets up Agate |

The build, deploy and syndication programs are not in this repo yet.

### Notes for the build

- Posts: line 1 is `# Title`, optional line 2 is `Published: YYYY-MM-DD`. Date and slug come from the filename.
- HTML link lines should be emitted as `<p class="link"><a href="…">…</a></p>`. The stylesheet draws the `⇒` marker so the page reads like a Gemini client.
- `static/_headers` holds the security headers; copy it to `dist/html/_headers`.

## First-time setup

### Cloudflare

1. Add `surfaced.run` as a zone and point the registrar at Cloudflare's nameservers.
2. Create an API token with **Zone › DNS › Edit**, **Zone › Zone Settings › Edit** and **Account › Workers Scripts › Edit**, limited to this zone and account. Export it as `CLOUDFLARE_API_TOKEN`.
3. Set up Email Routing for `security@surfaced.run` (referenced by `security.txt` and `SECURITY.md`).

### GCP

```bash
gcloud auth login
```

```bash
gcloud auth application-default login
```

```bash
gcloud config set project surfaced-blog
```

The project needs billing enabled. Then:

```bash
cd infra && terraform init && terraform apply
```

Terraform keeps state locally in `infra/terraform.tfstate`, which is gitignored. Back it up.

### HTTPS site

```bash
npm ci
```

```bash
npx wrangler deploy
```

The `custom_domain` route in `wrangler.jsonc` creates the apex DNS record and certificate for `surfaced.run`, so Terraform does not manage that record.

## Access to the VM

Port 22 is open only to Google's IAP range (`35.235.240.0/20`), not the internet. Both admin and deploy SSH go through an IAP tunnel, authenticated with your Google account.

Admin shell (OS Login, using the key in `infra/terraform.tfvars`):

```bash
gcloud compute ssh gemini --zone us-west1-b --tunnel-through-iap
```

Deploys go to the `deploy` user, which can only run `rrsync -wo /srv/gemini`. Paths are relative to `/srv/gemini`:

```bash
rsync -az --delete -e "ssh -o ProxyCommand='gcloud compute start-iap-tunnel gemini 22 --listen-on-stdin --zone us-west1-b'" dist/gemini/ deploy@gemini.surfaced.run:/
```

To SSH directly instead, add your IP to `ssh_source_ranges` in `infra/terraform.tfvars` and re-apply.

## Gemini TLS certificate

Agate generates its certificate on first start, in `/var/lib/agate/certs`. Gemini clients pin it, so don't lose it. Terraform ignores changes to the cloud-init and image, so editing them won't rebuild the VM. If you ever do rebuild it, copy that directory off first and restore it afterwards.
