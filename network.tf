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

# VPC, subnets and DNS
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


resource "google_compute_subnetwork" "proxy_subnet" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name          = "proxy-only-subnet"
  ip_cidr_range = "10.129.0.0/23"
  project       = var.project_id
  region        = var.project_default_region
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
  network       = google_compute_network.custom-vpc.id
}

resource "google_dns_managed_zone" "private_zone" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name     = "private"
  dns_name = "${var.private_domain}."
  project  = var.project_id

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.custom-vpc.id
    }
  }
}

resource "google_dns_record_set" "a" {
  depends_on = [
    google_project_service.gcp_services,
    google_compute_address.private-address,
    google_dns_managed_zone.private_zone
  ]

  project      = var.project_id
  name         = google_dns_managed_zone.private_zone.dns_name
  managed_zone = google_dns_managed_zone.private_zone.name
  type         = "A"
  ttl          = 300

  rrdatas = [google_compute_address.private-address.address]
}


# Global LB with https (http redirect to https), including Google managed certificate
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




# Internal LB with http url map
resource "google_compute_address" "private-address" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name         = "${var.project_id}-private-address"
  subnetwork   = google_compute_subnetwork.custom-subnet.id
  address_type = "INTERNAL"
  address      = "10.240.0.40"
  project      = var.project_id
  region       = var.project_default_region
  purpose      = "SHARED_LOADBALANCER_VIP"
}

resource "google_compute_forwarding_rule" "lb-frontend-cfg-nossl" {
  depends_on = [
    google_project_service.gcp_services,
    google_compute_subnetwork.proxy_subnet
  ]

  name                  = "lb-frontend-cfg-nossl"
  project               = var.project_id
  region                = var.project_default_region
  ip_protocol           = "TCP"
  ip_address            = google_compute_address.private-address.id
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_region_target_http_proxy.lb-frontend-nossl.id
  network               = google_compute_network.custom-vpc.id
  subnetwork            = google_compute_subnetwork.custom-subnet.id
  network_tier          = "PREMIUM"
}

resource "google_compute_region_target_http_proxy" "lb-frontend-nossl" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name    = "internal-lb-target-proxy"
  project = var.project_id
  region  = var.project_default_region
  url_map = google_compute_region_url_map.lb-frontend.id
}

# Regional URL map
resource "google_compute_region_url_map" "lb-frontend" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name            = "internal-lb"
  project         = var.project_id
  region          = var.project_default_region
  default_service = google_compute_region_backend_service.internal-backend-srv.id

  host_rule {
    hosts        = [var.private_domain]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_region_backend_service.internal-backend-srv.id

    path_rule {
      paths   = ["/pri/*"]
      service = google_compute_region_backend_service.internal-backend-srv.id
    }
  }
}

resource "google_vpc_access_connector" "frontend_to_internal" {
  name           = "frontend-to-internal"
  project        = var.project_id
  region         = var.project_default_region
  ip_cidr_range  = "10.8.0.0/28"
  machine_type   = "e2-micro"
  min_instances  = 2
  max_instances  = 10
  network        = google_compute_network.custom-vpc.id
  max_throughput = 1000
}

resource "google_iap_brand" "project_brand" {
  support_email     = var.iap_brand_support_email
  application_title = "Cloud IAP protected Application"
  project           = var.project_nmr
}

resource "google_iap_client" "project_client" {
  depends_on = [
    google_iap_brand.project_brand
  ]
  display_name = "LB Client"
  brand        = google_iap_brand.project_brand.name
}
