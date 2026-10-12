variable "gcp_project_id" {
  description = "GCP project that hosts the Gemini VM."
  type        = string
}

variable "region" {
  description = "Must be an Always Free e2-micro region."
  type        = string
  default     = "us-west1"
}

variable "zone" {
  type    = string
  default = "us-west1-b"
}

variable "domain" {
  description = "Apex domain. Must already be a zone in the Cloudflare account."
  type        = string
}

variable "gemini_subdomain" {
  type    = string
  default = "gemini"
}

variable "admin_ssh_public_key" {
  description = "Your personal key. Registered with OS Login for admin SSH."
  type        = string
}

variable "deploy_ssh_public_key" {
  description = "Key for the rsync-only deploy user. Ideally a dedicated key, separate from the admin key."
  type        = string
}

variable "ssh_source_ranges" {
  description = "CIDRs allowed to reach port 22. The default is Google's IAP TCP forwarding range only, so SSH works from anywhere through `gcloud ... --tunnel-through-iap` but the port is closed to the internet. Add your own IP as \"x.x.x.x/32\" to allow direct SSH."
  type        = list(string)
  default     = ["35.235.240.0/20"]
}

variable "agate_version" {
  type    = string
  default = "v3.3.24"
}

variable "agate_sha256" {
  description = "SHA-256 of agate.x86_64-unknown-linux-gnu.gz for agate_version."
  type        = string
  default     = "32379846ff14ce980377455bd935dd8635c56c61a0f336fb76aa461195110404"
}
