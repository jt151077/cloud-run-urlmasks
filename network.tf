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
### Custom VPC for the project
#
resource "google_compute_network" "custom_vpc" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name                    = "custom-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
}



############################################################
############# public services ##############################
############################################################

#
### Subnet for setting up the frontend (public) services
#
resource "google_compute_subnetwork" "frontend_subnet" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name          = "frontend-subnet"
  project       = var.project_id
  ip_cidr_range = "10.240.0.0/24"
  region        = var.project_default_region
  network       = google_compute_network.custom_vpc.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

#
### Public static IP address for the Global Load Balancer
#
resource "google_compute_global_address" "frontend_ip" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project    = var.project_id
  name       = "${var.project_id}-address"
  ip_version = "IPV4"
}

#
### Forwarding rule to HTTP Proxy for HTTP requests
#
resource "google_compute_global_forwarding_rule" "frontend_http_forward" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project    = var.project_id
  name       = "${var.project_id}-http"
  target     = google_compute_target_http_proxy.frontend_http_proxy.self_link
  ip_address = google_compute_global_address.frontend_ip.address
  port_range = "80"
}

#
### Forwarding rule to HTTPS Proxy for HTTPS requests
#
resource "google_compute_global_forwarding_rule" "frontend_https_forward" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project    = var.project_id
  name       = "${var.project_id}-https"
  target     = google_compute_target_https_proxy.frontend_https_proxy.self_link
  ip_address = google_compute_global_address.frontend_ip.address
  port_range = "443"
}

#
### Managed certificate for SSL termination on the Global Load Balancer
#
resource "google_compute_managed_ssl_certificate" "frontend_cert" {
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

#
### Global Target HTTP proxy 
#
resource "google_compute_target_http_proxy" "frontend_http_proxy" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project = var.project_id
  name    = "${var.project_id}-http-proxy"
  url_map = google_compute_url_map.frontend_https_redirect.self_link
}

#
### Global Target HTTPS proxy 
#
resource "google_compute_target_https_proxy" "frontend_https_proxy" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project = var.project_id
  name    = "${var.project_id}-https-proxy"
  url_map = google_compute_url_map.frontend_url_map.self_link

  ssl_certificates = [
    google_compute_managed_ssl_certificate.frontend_cert.self_link
  ]
}

#
### URL map for HTTP requests for permanent redirect to HTTPS
#
resource "google_compute_url_map" "frontend_https_redirect" {
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

#
### URL map for HTTPS requests towards Backend Service Global
#
resource "google_compute_url_map" "frontend_url_map" {
  depends_on = [
    google_compute_backend_service.frontend_global_backend_srv
  ]

  project         = var.project_id
  name            = "${var.project_id}-url-map"
  default_service = google_compute_backend_service.frontend_global_backend_srv.self_link

  host_rule {
    hosts        = [var.domain]
    path_matcher = var.path_matcher
  }

  path_matcher {
    name            = var.path_matcher
    default_service = google_compute_backend_service.frontend_global_backend_srv.self_link
  }
}

#
### Global Backend Service
#
resource "google_compute_backend_service" "frontend_global_backend_srv" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project = var.project_id
  name    = "frontend-backend-srv"

  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 30

  backend {
    group = google_compute_region_network_endpoint_group.frontend_serverless_neg.id
  }
}

#
### VPC Access connector to allow egress (outbound) traffic from Cloud Run to Compute Engine VM instances, Memorystore instances, and any other resources with an internal IP address
### Source: https://cloud.google.com/vpc/docs/configure-serverless-vpc-access
#
resource "google_vpc_access_connector" "frontend_to_internal" {
  name           = "frontend-to-internal"
  project        = var.project_id
  region         = var.project_default_region
  ip_cidr_range  = "10.8.0.0/28"
  machine_type   = "e2-micro"
  min_instances  = 2
  max_instances  = 10
  network        = google_compute_network.custom_vpc.id
  max_throughput = 1000
}





############################################################
############# private services #############################
############################################################

### Proxy-only Subnet for regional envoy-based load balancers
### Source: https://cloud.google.com/load-balancing/docs/l7-internal/setting-up-l7-internal#configure_the_proxy-only_subnet
#
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
  network       = google_compute_network.custom_vpc.id
}


#
### Subnet for setting up the backend (private) services
#
resource "google_compute_subnetwork" "backend_subnet" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name          = "backend-subnet"
  project       = var.project_id
  ip_cidr_range = "10.241.0.0/24"
  region        = var.project_default_region
  network       = google_compute_network.custom_vpc.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

#
### DNS private zone attached to the project to create a local private alias
#
resource "google_compute_address" "backend_private_address" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name         = "${var.project_id}-backend-private-address"
  subnetwork   = google_compute_subnetwork.backend_subnet.id
  address_type = "INTERNAL"
  address      = "10.241.0.40"
  project      = var.project_id
  region       = var.project_default_region
  purpose      = "SHARED_LOADBALANCER_VIP"
}

#
### DNS private zone attached to the project to create a local private alias
#
resource "google_dns_managed_zone" "backend_private_zone" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name     = "private"
  dns_name = "${var.private_domain}."
  project  = var.project_id

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.custom_vpc.id
    }
  }
}

#
### A Record to point to Internal Regional Load Balancer (attached to private address)
#
resource "google_dns_record_set" "backend_ilb_a" {
  depends_on = [
    google_project_service.gcp_services,
    google_compute_address.backend_private_address,
    google_dns_managed_zone.backend_private_zone
  ]

  project      = var.project_id
  name         = google_dns_managed_zone.backend_private_zone.dns_name
  managed_zone = google_dns_managed_zone.backend_private_zone.name
  type         = "A"
  ttl          = 300

  rrdatas = [google_compute_address.backend_private_address.address]
}

#
### Forwarding rule to HTTP Proxy for HTTP requests
#
resource "google_compute_forwarding_rule" "backend_http_forward" {
  depends_on = [
    google_project_service.gcp_services,
    google_compute_subnetwork.backend_subnet
  ]

  name                  = "${var.project_id}-backend-http"
  project               = var.project_id
  region                = var.project_default_region
  ip_protocol           = "TCP"
  ip_address            = google_compute_address.backend_private_address.id
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_region_target_http_proxy.backend_reg_http_proxy.id
  network               = google_compute_network.custom_vpc.id
  subnetwork            = google_compute_subnetwork.backend_subnet.id
  network_tier          = "PREMIUM"
}

#
### Global Target HTTP proxy 
#
resource "google_compute_region_target_http_proxy" "backend_reg_http_proxy" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name    = "${var.project_id}-backend-http-proxy"
  project = var.project_id
  region  = var.project_default_region
  url_map = google_compute_region_url_map.backend_url_map.id
}

#
### URL map for HTTP requests towards Backend Service Regional
#
resource "google_compute_region_url_map" "backend_url_map" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name            = "${var.project_id}-backend-url-map"
  project         = var.project_id
  region          = var.project_default_region
  default_service = google_compute_region_backend_service.backend_regional_backend_srv.id

  host_rule {
    hosts        = [var.private_domain]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_region_backend_service.backend_regional_backend_srv.id

    path_rule {
      paths   = ["/pri/*"]
      service = google_compute_region_backend_service.backend_regional_backend_srv.id
    }
  }
}

#
### Regional Backend Service
#
resource "google_compute_region_backend_service" "backend_regional_backend_srv" {
  name                  = "regional-backend-srv"
  project               = var.project_id
  region                = var.project_default_region
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"

  backend {
    balancing_mode = "UTILIZATION"
    group          = google_compute_region_network_endpoint_group.backend_servless_neg.id
  }
}
