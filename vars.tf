variable "project_id" {
  type = string
}

variable "project_nmr" {
  type = number
}

variable "project_default_region" {
  type = string
}

variable "domain" {
  type = string
}

variable "private_domain" {
  type = string
}


variable "default_run_image" {
  type    = string
  default = "nginx:latest"
}

variable "path_matcher" {
  type    = string
  default = "run"
}