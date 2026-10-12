output "gemini_ip" {
  value = google_compute_address.gemini.address
}

output "gemini_url" {
  value = "gemini://${local.gemini_host}/"
}

output "instance_name" {
  value = google_compute_instance.gemini.name
}

output "admin_ssh" {
  description = "Admin SSH through IAP, using OS Login."
  value       = "gcloud compute ssh ${google_compute_instance.gemini.name} --project ${var.gcp_project_id} --zone ${var.zone} --tunnel-through-iap"
}

output "deploy_rsync_ssh" {
  description = "Value for rsync -e when deploying through IAP."
  value       = "ssh -o ProxyCommand='gcloud compute start-iap-tunnel ${google_compute_instance.gemini.name} 22 --listen-on-stdin --project ${var.gcp_project_id} --zone ${var.zone}'"
}
