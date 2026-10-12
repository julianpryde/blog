terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.region
  zone    = var.zone
}

# Reads CLOUDFLARE_API_TOKEN from the environment.
provider "cloudflare" {}

locals {
  gemini_host = "${var.gemini_subdomain}.${var.domain}"
}

# ---------------------------------------------------------------- GCP APIs

resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "iap.googleapis.com",
    "oslogin.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------- Network
# A dedicated VPC instead of "default", which ships with allow-ssh/rdp/icmp
# rules open to 0.0.0.0/0. Ingress not allowed below is denied implicitly.

resource "google_compute_network" "gemini" {
  name                    = "gemini"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.services]
}

resource "google_compute_subnetwork" "gemini" {
  name          = "gemini-${var.region}"
  network       = google_compute_network.gemini.id
  region        = var.region
  ip_cidr_range = "10.10.0.0/24"
}

resource "google_compute_firewall" "allow_gemini" {
  name          = "allow-gemini"
  network       = google_compute_network.gemini.id
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gemini"]

  allow {
    protocol = "tcp"
    ports    = ["1965"]
  }
}

resource "google_compute_firewall" "allow_ssh" {
  name          = "allow-ssh-admin"
  network       = google_compute_network.gemini.id
  direction     = "INGRESS"
  source_ranges = var.ssh_source_ranges
  target_tags   = ["gemini"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Explicit, lowest-priority deny so the intent is visible in the console.
resource "google_compute_firewall" "deny_all_ingress" {
  name          = "deny-all-ingress"
  network       = google_compute_network.gemini.id
  direction     = "INGRESS"
  priority      = 65534
  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }
}

resource "google_compute_address" "gemini" {
  name         = "gemini"
  region       = var.region
  network_tier = "STANDARD"
  depends_on   = [google_project_service.services]
}

# ---------------------------------------------------------------- VM

# The VM calls no GCP APIs, so it gets an identity with no roles and no scopes.
resource "google_service_account" "gemini" {
  account_id   = "gemini-vm"
  display_name = "Gemini VM (no permissions)"
}

resource "google_compute_instance" "gemini" {
  name         = "gemini"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["gemini"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-13"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.gemini.id
    access_config {
      nat_ip       = google_compute_address.gemini.address
      network_tier = "STANDARD"
    }
  }

  service_account {
    email  = google_service_account.gemini.email
    scopes = []
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    user-data = templatefile("${path.module}/cloud-init.yaml", {
      gemini_host           = local.gemini_host
      agate_version         = var.agate_version
      agate_sha256          = var.agate_sha256
      deploy_ssh_public_key = var.deploy_ssh_public_key
    })
  }

  # cloud-init only runs on first boot. Changing it should not silently
  # recreate the VM, which would also throw away the pinned TLS certificate.
  lifecycle {
    ignore_changes = [metadata["user-data"], boot_disk[0].initialize_params[0].image]
  }
}

# Admin SSH key, registered to whoever runs Terraform (OS Login ignores
# metadata ssh-keys).
data "google_client_openid_userinfo" "me" {}

resource "google_os_login_ssh_public_key" "admin" {
  user       = data.google_client_openid_userinfo.me.email
  key        = var.admin_ssh_public_key
  depends_on = [google_project_service.services]
}

# ---------------------------------------------------------------- Cloudflare
# The apex record is created by `wrangler deploy` (custom_domain route in
# wrangler.jsonc), so only the Gemini record is managed here.

data "cloudflare_zone" "site" {
  filter = {
    name = var.domain
  }
}

# DNS only: Cloudflare does not proxy port 1965.
resource "cloudflare_dns_record" "gemini" {
  zone_id = data.cloudflare_zone.site.zone_id
  name    = local.gemini_host
  type    = "A"
  content = google_compute_address.gemini.address
  proxied = false
  ttl     = 3600
}

resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = data.cloudflare_zone.site.zone_id
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = data.cloudflare_zone.site.zone_id
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "ssl" {
  zone_id    = data.cloudflare_zone.site.zone_id
  setting_id = "ssl"
  value      = "strict"
}

# HSTS. Start without preload; add it once the site has run cleanly for a while.
resource "cloudflare_zone_setting" "hsts" {
  zone_id    = data.cloudflare_zone.site.zone_id
  setting_id = "security_header"
  value = {
    strict_transport_security = {
      enabled            = true
      max_age            = 31536000
      include_subdomains = true
      preload            = false
      nosniff            = true
    }
  }
}
