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


resource "google_compute_network" "custom-vpc" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name                    = "custom-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "custom-subnet" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name          = "custom-subnet"
  project       = var.project_id
  ip_cidr_range = "10.240.0.0/24"
  region        = var.project_default_region
  network       = google_compute_network.custom-vpc.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "ilb-subnet" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name          = "ilb-subnet"
  project       = var.project_id
  ip_cidr_range = "10.1.2.0/24"
  region        = var.project_default_region
  network       = google_compute_network.custom-vpc.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}


# LB with https (http redirect to https)
resource "google_compute_target_http_proxy" "default" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project = var.project_id
  name    = "${var.project_id}-http-proxy"
  url_map = google_compute_url_map.https_redirect.self_link
}

resource "google_compute_target_https_proxy" "default" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project = var.project_id
  name    = "${var.project_id}-https-proxy"
  url_map = google_compute_url_map.default.self_link

  ssl_certificates = [
    google_compute_managed_ssl_certificate.default.self_link
  ]
}

resource "google_compute_managed_ssl_certificate" "default" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project = var.project_id
  name    = "${var.project_id}-cert"

  lifecycle {
    create_before_destroy = true
  }

  managed {
    domains = [var.domain]
  }
}

resource "google_compute_url_map" "default" {
  depends_on = [
    google_compute_backend_service.run-backend-srv
  ]

  project         = var.project_id
  name            = "${var.project_id}-url-map"
  default_service = google_compute_backend_service.run-backend-srv.self_link

  host_rule {
    hosts        = [var.domain]
    path_matcher = var.path_matcher
  }

  path_matcher {
    name            = var.path_matcher
    default_service = google_compute_backend_service.run-backend-srv.self_link
  }
}

resource "google_compute_url_map" "https_redirect" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project = var.project_id
  name    = "${var.project_id}-https-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_global_forwarding_rule" "http" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project    = var.project_id
  name       = "${var.project_id}-http"
  target     = google_compute_target_http_proxy.default.self_link
  ip_address = google_compute_global_address.default.address
  port_range = "80"
}

resource "google_compute_global_forwarding_rule" "https" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project    = var.project_id
  name       = "${var.project_id}-https"
  target     = google_compute_target_https_proxy.default.self_link
  ip_address = google_compute_global_address.default.address
  port_range = "443"
}

resource "google_compute_global_address" "default" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project    = var.project_id
  name       = "${var.project_id}-address"
  ip_version = "IPV4"
}

resource "google_compute_router" "router" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name    = "router"
  project = var.project_id
  region  = var.project_default_region
  network = google_compute_network.custom-vpc.id
}

resource "google_compute_router_nat" "nat" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name    = "nat"
  project = var.project_id
  region  = var.project_default_region
  router  = google_compute_router.router.name

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.custom-subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  nat_ip_allocate_option = "AUTO_ONLY"
}

resource "google_compute_firewall" "default" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project = var.project_id
  name    = "allow-tcp-traffic"
  network = google_compute_network.custom-vpc.id

  #tfsec:ignore:google-compute-no-public-ingress
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

output "lb_external_ip" {
  value = google_compute_global_address.default.address
}
