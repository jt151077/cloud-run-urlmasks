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


# internal applications on Cloud Run
resource "google_cloud_run_service" "backend_runs" {
  depends_on = [
    google_project_service.gcp_services
  ]

  count = length(local.service_ids)
  name  = local.service_ids[count.index]

  project  = var.project_id
  location = var.project_default_region

  metadata {
    annotations = {
      "run.googleapis.com/ingress" : "internal-and-cloud-load-balancing"
    }
  }

  template {
    spec {
      service_account_name = google_service_account.cloudrun_service_account.email
      containers {
        image = var.default_run_image

        ports {
          container_port = 80
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].spec[0].containers[0].image,
      template[0].spec[0].service_account_name,
      metadata[0].annotations["run.googleapis.com/operation-id"],
      metadata[0].annotations["client.knative.dev/user-image"],
      metadata[0].annotations["run.googleapis.com/client-name"],
      metadata[0].annotations["run.googleapis.com/client-version"]
    ]
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}


resource "google_compute_region_network_endpoint_group" "internal_servless_neg" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name                  = "internal-servless-neg"
  network_endpoint_type = "SERVERLESS"
  project               = var.project_id
  region                = var.project_default_region

  cloud_run {
    url_mask = "/pri/<service>"
  }
}


resource "google_compute_region_backend_service" "internal-backend-srv" {
  name                  = "internal-backend-srv"
  project               = var.project_id
  region                = var.project_default_region
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"

  backend {
    balancing_mode = "UTILIZATION"
    group          = google_compute_region_network_endpoint_group.internal_servless_neg.id
  }
}


# frontend Cloud Run application
resource "google_cloud_run_service" "frontend" {
  depends_on = [
    google_project_service.gcp_services
  ]

  name = "frontend"

  project  = var.project_id
  location = var.project_default_region

  metadata {
    annotations = {
      "run.googleapis.com/ingress" : "internal-and-cloud-load-balancing"
    }
  }

  template {
    spec {
      service_account_name = google_service_account.cloudrun_service_account.email
      containers {
        image = var.default_run_image

        ports {
          container_port = 80
        }
      }
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"        = 4
        "autoscaling.knative.dev/minScale"        = 2
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.frontend_to_internal.id
        "run.googleapis.com/vpc-access-egress"    = "all-traffic"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].spec[0].containers[0].image,
      template[0].spec[0].service_account_name,
      template[0].metadata[0].annotations["run.googleapis.com/client-name"],
      template[0].metadata[0].annotations["run.googleapis.com/client-version"],
      template[0].metadata[0].labels["run.googleapis.com/startupProbeType"],
      metadata[0].annotations["run.googleapis.com/operation-id"],
      metadata[0].annotations["client.knative.dev/user-image"],
      metadata[0].annotations["run.googleapis.com/client-name"],
      metadata[0].annotations["run.googleapis.com/client-version"]
    ]
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  depends_on = [
    google_project_service.gcp_services
  ]

  provider              = google-beta
  name                  = "serverless-neg"
  network_endpoint_type = "SERVERLESS"
  project               = var.project_id
  region                = var.project_default_region

  cloud_run {
    service = google_cloud_run_service.frontend.name
  }
}

resource "google_compute_backend_service" "run-backend-srv" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project = var.project_id
  name    = "run-backend-srv"

  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 30

  backend {
    group = google_compute_region_network_endpoint_group.serverless_neg.id
  }
}


