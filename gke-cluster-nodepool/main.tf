/* ============================================================================================
# In order to plan / apply this file on Terraform Cloud:
# Create account, workspace, etc.
# Associate repo with this file with workspace. If this main.tf is under a subfolder of the repo as opposed to root,
# specify working directory while associating repo with TFC workspace
# Configure "Variables" in the workspace.
# Create GCP Service Account Key like this (following steps to use the key on local dev machine terraform command):
# 	STEP 1. On GCP Console, visit IAM & Admin --> Service Accounts
# 	STEP 2. Create a new Service Account, like "terraform-service-account"
# 	STEP 3. Add appropriate permission, like Compute Engine Admin, Network Management Admin, etc.
# 	STEP 4. Once created, click the ellipsis (three dots) and select "Create Key", choose JSON
# 	STEP 5. Save it on hard disk - somewhere safe
# 	STEP 6. Add an environment variable pointing at the full path of this JSON file:
          export GOOGLE_CLOUD_KEYFILE_JSON="/path/to/credentials.json"
# 	STEP 7. To make the environment variable permanent, add the same line in ~/.bashrc
# In order to do the same in TFC:
# 	1. Configure "Variables" in the workspace
# 	2. Add environment variable GOOGLE_CLOUD_KEYFILE_JSON
# 	3. Its value should be: the contents of the above json file with all newlines stripped
# 	  To strip all new lines, open the key file in vi and issue command :%s/\n/
# 	  Then copy using mouse and paste on TFC
# 	  Mark variable as sensitive
# =========================================================================================== */

provider "google" {
        project         	= "cr-lab-kbiswas-2304204819"
	version			= "~> 3.20"
	region			= "us-central1"
	zone			= "us-central1-c"
}

resource "google_container_cluster" "primary" {
  name     = "my-gke-cluster"
  location = "us-central1"

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1
  default_max_pods_per_node = 4
}

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "my-node-pool"
  location   = "us-central1"
  cluster    = google_container_cluster.primary.name
  max_pods_per_node = 4

  node_config {
    preemptible  = true
    machine_type = "n1-standard-1"

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 10
  }
}
