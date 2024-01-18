# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
data "google_client_config" "default" {}

variable "gke_username" {
  default     = ""
  description = "gke username"
}

variable "gke_password" {
  default     = ""
  description = "gke password"
}

variable "gke_num_nodes" {
  default     = 1
  description = "number of gke nodes"
}

# GKE cluster
data "google_container_engine_versions" "gke_version" {
  location = var.region
  version_prefix = "1.27."
}

resource "google_container_cluster" "primary" {
  name     = "${var.project_id}-gke"
  location = var.region
  
  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    disk_size_gb = 50
  }
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
}

# Separately Managed Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = google_container_cluster.primary.name
  location   = var.region
  cluster    = google_container_cluster.primary.name
  
  version = data.google_container_engine_versions.gke_version.release_channel_latest_version["STABLE"]
  node_count = var.gke_num_nodes
  

  node_config {
    disk_size_gb = 50
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels = {
      env = var.project_id
    }

    # preemptible  = true
    machine_type = "n1-standard-1"
    tags         = ["gke-node", "${var.project_id}-gke"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}


# # Kubernetes provider
# # The Terraform Kubernetes Provider configuration below is used as a learning reference only. 
# # It references the variables and resources provisioned in this file. 
# # We recommend you put this in another file -- so you can have a more modular configuration.
# # https://learn.hashicorp.com/terraform/kubernetes/provision-gke-cluster#optional-configure-terraform-kubernetes-provider
# # To learn how to schedule deployments and services using the provider, go here: https://learn.hashicorp.com/tutorials/terraform/kubernetes-provider.

# provider "kubernetes" {
#   load_config_file = "false"

#   host     = google_container_cluster.primary.endpoint
#   username = var.gke_username
#   password = var.gke_password

#   client_certificate     = google_container_cluster.primary.master_auth.0.client_certificate
#   client_key             = google_container_cluster.primary.master_auth.0.client_key
#   cluster_ca_certificate = google_container_cluster.primary.master_auth.0.cluster_ca_certificate
# }

# ... Votre configuration existante ...

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = google_container_cluster.primary.endpoint
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

resource "kubernetes_namespace" "nginx_ns" {
  metadata {
    name = "nginx-namespace"
  }
}

resource "kubernetes_namespace" "grafana_ns" {
  metadata {
    name = "grafana-namespace"
  }
}


# Nginx Deployment
resource "kubernetes_deployment" "nginx" {
  metadata {
    name = "nginx-deployment"
    namespace = kubernetes_namespace.nginx_ns.metadata[0].name

  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "nginx"
      }
    }
    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }
      spec {
        container {
          image = "nginx:latest"
          name  = "nginx"
          port {
            container_port = 80
          }
        }
      }
    }
  }
}

# Grafana Deployment
resource "kubernetes_deployment" "grafana" {
  metadata {
    name = "grafana-deployment"
    
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "grafana"
      }
    }
    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }
      spec {
        container {
          image = "grafana/grafana:latest"
          name  = "grafana"
          port {
            container_port = 3000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "nginx_lb" {
  metadata {
    name = "nginx-loadbalancer"
    namespace = kubernetes_namespace.nginx_ns.metadata[0].name

  }

  spec {
    selector = {
      app = kubernetes_deployment.nginx.spec.0.template.0.metadata[0].labels["app"]
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }
}

resource "google_service_account" "cloud_function_account" {
  account_id   = "cloud-function-account"
  display_name = "Cloud Function Service Account"
}

resource "google_cloudfunctions_function" "my_function" {
  name                  = "my-cloud-function"
  runtime               = "python38" 
  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.cloud_function_bucket.name
  source_archive_object = google_storage_bucket_object.cloud_function_archive.name
  entry_point           = "main"
  service_account_email = google_service_account.cloud_function_account.email
  trigger_http          = true

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.scheduler_topic.id
  }
}

resource "google_cloud_scheduler_job" "function_scheduler" {
  name     = "function-scheduler"
  schedule = "0 7 * * *"

  pubsub_target {
    topic_name = google_pubsub_topic.scheduler_topic.id
    data       = base64encode("CURL Nginx")
  }
}

resource "google_pubsub_topic" "scheduler_topic" {
  name = "scheduler-topic"
}


