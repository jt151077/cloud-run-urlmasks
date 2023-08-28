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


resource "google_service_account" "cloudrun_service_account" {
  depends_on = [
    google_project_service.gcp_services
  ]

  project    = var.project_id
  account_id = "cloudrun-sa"
}

resource "google_project_iam_member" "run_artifactregistry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.cloudrun_service_account.email}"
}

resource "google_project_iam_member" "run_logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudrun_service_account.email}"
}


resource "google_cloud_run_service_iam_binding" "frontend" {
  location = var.project_default_region
  project  = var.project_id
  service  = google_cloud_run_service.frontend.name
  role     = "roles/run.invoker"
  members = [
    "allUsers"
  ]
}

resource "google_cloud_run_service_iam_binding" "default" {
  count = length(local.service_ids)

  project  = var.project_id
  location = var.project_default_region
  service  = google_cloud_run_service.backend_runs[count.index].name
  role     = "roles/run.invoker"
  members = [
    "allUsers"
  ]
}


resource "google_iap_web_backend_service_iam_binding" "run-binding" {
  depends_on = [
    google_compute_backend_service.run-backend-srv
  ]
  project             = var.project_id
  web_backend_service = google_compute_backend_service.run-backend-srv.name
  role                = "roles/iap.httpsResourceAccessor"
  members = [
    "user:${local.iap_brand_support_email}",
  ]
}