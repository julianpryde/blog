# Surfaced

A static blog about secure software development, served at https://surfaced.run/ and gemini://gemini.surfaced.run/. Some posts are Gemini-only. See `PLAN.md` for the design.

## Layout

Content lives outside this repo so some of it can be published over Gemini only. Two environment variables point at the two directories:

| Variable | Directory |
| --- | --- |
| `$BLOG_CONTENT` | Gemtext source: `index.gmi`, `about.gmi`, `posts/YYYY-MM-DD-slug.gmi` |
| `$BLOG_INFRA` | This repo: templates, static files, build output, deploy config, infrastructure |

| Path in this repo | Purpose |
| --- | --- |
| `dist/html/` | Built HTTPS site. Tracked in git |
| `dist/gemtext/` | Built Gemini capsule. Not tracked |
| `templates/page.html` | HTML shell. Placeholders: `{{title}}`, `{{body}}`, `{{canonical_https}}`, `{{canonical_gemini}}` |
| `static/` | Copied into the output. `style.css` and `_headers` go to HTML only; `.well-known/` goes to both |
| `wrangler.jsonc`, `package.json` | Assets-only Worker for the HTTPS site, wrangler pinned |
| `infra/` | Terraform for the GCP VM, firewall, static IP and Cloudflare DNS/zone settings; `cloud-init.yaml` sets up Agate |

The build, deploy and syndication programs are not in this repo yet.

### Notes for the build

- Posts: line 1 is `# Title`, optional line 2 is `Published: YYYY-MM-DD`. Date and slug come from the filename.
- HTML link lines should be emitted as `<p class="link"><a href="…">…</a></p>`. The stylesheet draws the `⇒` marker so the page reads like a Gemini client.
- `static/_headers` holds the security headers; copy it to `dist/html/_headers`.
- Gemini-only content must be left out of `dist/html/` entirely, including the HTML index, the HTML Atom feed and any links from HTML pages. Since `dist/html/` is committed, check `git diff dist/html` before pushing so nothing Gemini-only ends up on GitHub.

## First-time setup

### Cloudflare

1. Add `surfaced.run` as a zone and point the registrar at Cloudflare's nameservers.
2. Create a custom API token. Zone permissions should be limited to `surfaced.run`, and account permissions to your account:

   | Scope | Permission | Level | Used by |
   | --- | --- | --- | --- |
   | Zone | Zone | Read | Terraform zone lookup, wrangler |
   | Zone | DNS | Edit | Terraform `gemini` record, wrangler custom domain |
   | Zone | Zone Settings | Edit | Terraform HTTPS/TLS/HSTS settings |
   | Zone | Workers Routes | Edit | wrangler custom domain |
   | Account | Workers | Admin, then Editor | wrangler deploy |

   Workers Editor can deploy to an existing Worker but can't create one, so the first `wrangler deploy` needs Workers Admin. Once the `surfaced` Worker exists, you can swap Admin for Editor. Workers permissions are account-scoped, so put them only in the account policy, not the zone policy.

   The account-level DNS groups (Account DNS Settings, DNS Firewall, DNS Views, Registrar) aren't needed, and neither are Workers Containers, KV or R2. Export the token as `CLOUDFLARE_API_TOKEN`, and set `CLOUDFLARE_ACCOUNT_ID` so wrangler doesn't need permission to list your accounts.
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
rsync -az --delete -e "ssh -o ProxyCommand='gcloud compute start-iap-tunnel gemini 22 --listen-on-stdin --zone us-west1-b'" dist/gemtext/ deploy@gemini.surfaced.run:/
```

To SSH directly instead, add your IP to `ssh_source_ranges` in `infra/terraform.tfvars` and re-apply.

## Gemini TLS certificate

Agate generates its certificate on first start, in `/var/lib/agate/certs`. Gemini clients pin it, so don't lose it. Terraform ignores changes to the cloud-init and image, so editing them won't rebuild the VM. If you ever do rebuild it, copy that directory off first and restore it afterwards.
