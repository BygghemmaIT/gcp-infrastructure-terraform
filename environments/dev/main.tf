locals {
  env = "prod"
  slim_project_id = "bh-slim-test"
  host_network = "bghprod"
  slim_network = "bhtest-europe-north1"
  cloudrun_network = "bhtest-cr-europe-north1"
}

module "slim_project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "14.2.0"
  
  name                = local.slim_project_id
  billing_account     = var.billing_account
  org_id              = var.org_id
  folder_id           = var.folder_id
  random_project_id   = true
  svpc_host_project_id = var.vpc_host_project_id
  shared_vpc_subnets = [
    "projects/${var.vpc_host_project_id}/regions/${var.region}/subnetworks/${local.slim_network}",
    "projects/${var.vpc_host_project_id}/regions/${var.region}/subnetworks/${local.cloudrun_network}"
  ]
  activate_apis = ["compute.googleapis.com", "container.googleapis.com", "run.googleapis.com", "pubsub.googleapis.com", "secretmanager.googleapis.com", "vpcaccess.googleapis.com"]
}

module "vpc-serverless-connector-beta" {
  source     = "terraform-google-modules/network/google//modules/vpc-serverless-connector-beta"
  project_id = module.slim_project.project_id
  vpc_connectors = [{
    name            = "cloudrun-vpc-connector"
    region          = var.region
    subnet_name     = local.cloudrun_network
    host_project_id = var.vpc_host_project_id
    machine_type    = "f1-micro"
    min_instances   = 2
    max_instances   = 10
    max_throughput  = 1000
  }]
}

resource "google_project_iam_member" "developer-slim" {
  for_each = toset( ["roles/cloudtasks.admin","roles/iam.serviceAccountCreator","roles/iam.serviceAccountUser","roles/pubsub.admin","roles/run.developer","roles/storage.admin"] )
  project = module.slim_project.project_id
  role    = each.key
  member  = "group:developer@bygghemma.se"
}

resource "google_project_iam_member" "legacy-build" {
  project = module.slim_project.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:1016006425732@cloudbuild.gserviceaccount.com"
}

module "slim_gke" {
  source  = "terraform-google-modules/kubernetes-engine/google"
  version = "25.0.0"
  
  name = "bh-slim-test"
  project_id = module.slim_project.project_id

  network_project_id  = var.vpc_host_project_id
  network             = local.host_network
  subnetwork          = local.slim_network
  ip_range_pods       = "pods"
  ip_range_services   = "services"

  regional  = false
  zones     = ["europe-north1-b"]

  monitoring_enable_managed_prometheus = true
  enable_vertical_pod_autoscaling = true
  release_channel = "STABLE"

  logging_enabled_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]

  remove_default_node_pool = true
  node_pools = [
    {
      name                      = "default-node-pool"
      machine_type              = "e2-medium"
      min_count                 = 1
      max_count                 = 20
      local_ssd_count           = 0
      spot                      = false
      disk_size_gb              = 75
      disk_type                 = "pd-standard"
      image_type                = "COS_CONTAINERD"
      enable_gcfs               = false
      enable_gvnic              = false
      auto_repair               = true
      auto_upgrade              = true
      preemptible               = false
      initial_node_count        = 1
    },
    {
      name                      = "spot-node-pool"
      machine_type              = "e2-medium"
      min_count                 = 1
      max_count                 = 20
      local_ssd_count           = 0
      spot                      = true
      disk_size_gb              = 75
      disk_type                 = "pd-standard"
      image_type                = "COS_CONTAINERD"
      enable_gcfs               = false
      enable_gvnic              = false
      auto_repair               = true
      auto_upgrade              = true
      preemptible               = false
      initial_node_count        = 1
    }
  ]

  node_pools_labels = {
    all = {}

    default-node-pool = {
      default-node-pool = true
    }
  }

  node_pools_taints = {
    all = []

    spot-node-pool = [
      {
        key    = "cloud.google.com/gke-spot"
        value  = true
        effect = "NO_SCHEDULE"
      }
    ]
  }

}
