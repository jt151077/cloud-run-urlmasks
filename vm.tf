/**
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


#
### Google Compute Engine with linux preinstalled
#
resource "google_compute_instance" "dev_vm" {
  depends_on = [
    google_compute_subnetwork.vm_subnet
  ]

  name                      = "dev-vm"
  zone                      = "${var.project_default_region}-b"
  project                   = var.project_id
  machine_type              = "e2-micro"
  allow_stopping_for_update = true
  tags                      = ["ssh"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.vm_subnet.self_link
  }

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.dev_vm_sa.email
    scopes = ["cloud-platform"]
  }
}

#
### Firewall rule to allow SSH on GCE
#
resource "google_compute_firewall" "ssh" {
  depends_on = [
    google_compute_network.custom_vpc
  ]

  project = var.project_id
  name    = "allow-ssh"

  allow {
    ports    = ["22"]
    protocol = "tcp"
  }

  direction     = "INGRESS"
  network       = google_compute_network.custom_vpc.id
  priority      = 1000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh"]
}
