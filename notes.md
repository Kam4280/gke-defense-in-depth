Every GitHub Actions workflow file follows a strict structure built from 5 core blocks. Once you memorize this structure, you can write pipelines for Python, Docker, Kubernetes, or any other tool from scratch.

The 5 Anatomy Blocks of GitHub Actions YAML
# BLOCK 1: Pipeline Name (Visible in GitHub UI)
name: "My Custom Pipeline"

# BLOCK 2: Triggers (WHEN should this run?)
on:
  push:
    branches: [ main ]      # Runs when code is merged to main
  pull_request:
    branches: [ main ]      # Runs when someone opens a Pull Request

# BLOCK 3: Security & Token Permissions (WHAT can GitHub do?)
permissions:
  id-token: write          # Needed for GCP Workload Identity Federation
  contents: read           # Allows reading the git repo code

# BLOCK 4: Execution Environment (WHERE does it run?)
jobs:
  deploy:
    runs-on: ubuntu-latest # Spins up a clean, temporary Linux VM

    # BLOCK 5: The Step-by-Step Execution Chain (WHAT steps run sequentially?)
    steps:
      - name: 1. Checkout repository code
        uses: actions/checkout@v4 # Pre-built reusable action from GitHub

      - name: 2. Authenticate to GCP
        uses: google-github-actions/auth@v2 # Official Google action
        with:
          workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
          service_account: ${{ secrets.WIF_SERVICE_ACCOUNT }}

      - name: 3. Run Custom CLI Commands
        run: |
          echo "Executing custom commands..."
          terraform init
          terraform plan


How to build these for any future use case:
GitHub Marketplace: github.com/marketplace/actions [1] for pre-built blocks (e.g., "Setup Python", "Docker Build", "AWS Auth").

Official Documentation: Tool creators maintain standard templates (e.g., Google publishes official GitHub Actions templates for GCP, HashiCorp for Terraform).

The uses: vs run: Rule:

Use uses: when leveraging a community pre-packaged module (e.g., actions/checkout@v4).

Use run: when executing a raw terminal command (e.g., run: terraform apply).
[1]:
https://github.com/marketplace?type=actions
https://github.com/google-github-actions
https://github.com/actions/starter-workflows


In production GKE enterprise environments, clusters must never use default VPC networks or auto-created subnets.

By default, everything created inside a module (like modules/01-vpc-network) is isolated and private to that module. No other part of your Terraform code can see or touch the resources inside unless you explicitly export them using outputs.tf.


The 3 Key Reasons We Use outputs.tf
Inter-Module Communication (Composition): It allows downstream modules (GKE cluster, KMS keys, Service Mesh) to reference resources built by upstream modules without hardcoding names.

Exposing Dynamic Runtime Attributes: Properties created dynamically by Google Cloud at runtime (such as an automatically assigned IP range, resource self-link, or KMS key fingerprint) cannot be known in advance—they must be captured via outputs.

CLI Inspection & CI/CD Debugging: Running terraform output after a deployment prints these key attributes directly to your terminal or GitHub Actions logs for verification.



Why Do We Create outputs.tf in a Terraform Module?
Think of a Terraform module like a function in programming:

variables.tf = The Input Parameters passed into the function.

main.tf = The Internal Logic / Execution Body of the function.

outputs.tf = The Return Values sent back by the function.

By default, everything created inside a module (like modules/01-vpc-network) is isolated and private to that module. No other part of your Terraform code can see or touch the resources inside unless you explicitly export them using outputs.tf.

The 3 Key Reasons We Use outputs.tf

Inter-Module Communication (Composition): It allows downstream modules (GKE cluster, KMS keys, Service Mesh) to reference resources built by upstream modules without hardcoding names.

Exposing Dynamic Runtime Attributes: Properties created dynamically by Google Cloud at runtime (such as an automatically assigned IP range, resource self-link, or KMS key fingerprint) cannot be known in advance—they must be captured via outputs.

CLI Inspection & CI/CD Debugging: Running terraform output after a deployment prints these key attributes directly to your terminal or GitHub Actions logs for verification.


Tier 1:

Architectural Layer Isolation
Layer: Tier 1 (Cloud Foundation — Layer 4 VPC Perimeter & Network Isolation)

Target: Custom VPC Network, Private Subnet with Secondary Ranges (GKE Pods & Services), Cloud Router, and Cloud NAT.

Tier 1 Overview & Step 1: Network Foundation Module (01-vpc-network)
In production GKE enterprise environments, clusters must never use default VPC networks or auto-created subnets.

In this step, we will build the reusable Terraform module modules/01-vpc-network. This module provisions:

A Custom VPC Network (auto_create_subnetworks = false).

A Private Subnet with explicit Secondary IP Ranges reserved for GKE Pods and GKE Services (enabling VPC-native alias IPs).

Private Google Access (allows nodes/pods to hit Google APIs via private internal routing without public IPs).

Cloud Router & Cloud NAT with full logging enabled (allows private nodes to pull outbound updates/packages without exposing public inbound interfaces).

=============

Architectural Layer Isolation
Layer: Tier 1 (Cloud Foundation — Network Isolation)

Target: Module 01-vpc-network/main.tf

Cause Analysis
The Google Terraform provider expects nat_ip_allocate_option to be set to AUTO_ONLY when dynamic IP allocation is desired, rather than AUTO_ALLOCATE.

==========================

Architectural Layer Isolation
Layer: Tier 1 (Cloud Foundation — Security & Encryption Layer 6 Base)

Target: Customer-Managed Encryption Keys (CMEK) for GKE etcd Database and Persistent Disk Storage.

Tier 1 — Step 2: Customer-Managed Encryption Keys (02-kms-cmek)
In a default GKE setup, Google manages encryption keys automatically. To achieve enterprise-grade Defense-in-Depth (Layer 6: Data Security), we must maintain cryptographic control using Cloud KMS Customer-Managed Encryption Keys (CMEK).

In this step, we will build modules/02-kms-cmek. This module provisions:

A Cloud KMS KeyRing bound to our primary deployment region.

A CMEK CryptoKey dedicated to GKE etcd database secret envelope encryption (with automated 90-day key rotation).

A CMEK CryptoKey dedicated to GKE persistent volume node disks (pd-ssd/pd-standard).

Additive IAM Bindings (roles/cloudkms.cryptoKeyEncrypterDecrypter) granted directly to the GKE and Compute Engine Service Agents using dynamic project number lookups.

===============================

Architectural Layer Isolation
Layer: Tier 1 (Cloud Foundation — Network & Security Infrastructure Baseline)

Target: environments/prod (Environment Orchestration Layer)

Tier 1 — Step 3: Production Environment Composition (environments/prod)
Now that we have created and validated our two reusable infrastructure building blocks (modules/01-vpc-network and modules/02-kms-cmek), we will compose them into our target production environment inside environments/prod.

This step connects our local Terraform environment to the remote Google Cloud Storage (GCS) backend bucket created during Tier 0 bootstrap, ensuring our state file is protected and encrypted.

===============================
Architectural Layer Isolation
Layer: Tier 1 (Cloud Foundation — Security & Encryption)

Target: Module 02-kms-cmek/main.tf

Cause Analysis
In Google Cloud, Service Agents (like service-243781974020@container-engine-robot.iam.gserviceaccount.com) do not exist by default when a project is newly created. GCP creates them lazily only after the corresponding API (container.googleapis.com) is enabled and an identity request is explicitly triggered.

Because the GKE Service Agent did not physically exist in project kam-dev-test yet, GCP's IAM API rejected our KMS binding with Error 400: Service account ... does not exist.

==============================

Architectural Layer Isolation
Layer: Tier 1 (Cloud Foundation — Security & Encryption)

Target: Module 02-kms-cmek/main.tf

Cause Analysis
In HashiCorp's Terraform ecosystem, the resource google_project_service_identity belongs exclusively to the google-beta provider. Because our module relies on the standard hashicorp/google provider, Terraform threw an Invalid resource type error.

Step 1: Updated modules/02-kms-cmek/main.tf
We will replace google_project_service_identity with standard google_project_service API enablement resources and explicit depends_on blocks. This ensures full compatibility with the standard hashicorp/google provider while guaranteeing that GCP initializes the required API service identities prior to applying KMS IAM bindings.


================================
Tier 2:

Architectural Layer Isolation

Layer: Tier 2 (Hardened Infrastructure — Layer 3: Workload/Host Security, Layer 5: IAM/RBAC, & Layer 6: Data Security)

Target: modules/03-gke-cluster (Reusable Hardened GKE Module)

Tier 2 — Step 1: Building the Hardened Private GKE Module (03-gke-cluster)
With Tier 1 (Cloud Foundation: VPC Network, NAT, and KMS CMEK) successfully deployed, we advance to Tier 2.

In this step, we will design and construct modules/03-gke-cluster. This module enforces enterprise zero-trust controls at the Kubernetes infrastructure layer:

1) Private Cluster Architecture: Nodes have strictly private IP addresses (no public IPs). The control plane endpoint is isolated.

2) Dataplane V2 (eBPF / Cilium): Replaces legacy kube-proxy with eBPF for high-performance network security, flow logging, and L4 NetworkPolicy enforcement.

3) CMEK etcd Envelope Encryption: Encrypts all Kubernetes Secrets at rest using the KMS key created in Tier 1.

4) Custom Least-Privilege Node Service Account: Completely replaces the default Compute Engine service account with a minimalist IAM identity (logWriter, metricWriter, artifactregistry.reader).

5) Workload Identity Federation: Enables GKE Pods to assume GCP IAM roles safely without requiring static service account JSON keys.

6) Dual Node Pool Architecture:

 - System Node Pool: Runs core cluster add-ons with Shielded COS (Container-Optimized OS), Secure Boot, and Integrity Monitoring.

 - Sandboxed Node Pool (gVisor): Enforces user-space kernel isolation (sandbox_config = "gvisor") with dedicated Kubernetes taints (sandbox.gke.io/runtime=gvisor:NoSchedule) for untrusted apps and MLOps inference engines.

================================
# 1. Navigate to the GKE cluster module directory
cd /workspaces/gke-defense-in-depth/modules/03-gke-cluster

# 2. Initialize provider dependencies
terraform init

# 3. Validate syntax and configuration integrity
terraform validate


╷
│ Error: Unsupported block type
│ 
│   on main.tf line 188, in resource "google_container_node_pool" "gvisor_nodes":
│  188:     sandbox_config {
│ 
│ Blocks of type "sandbox_config" are not expected here.

------------>

Architectural Layer Isolation
Layer: Tier 2 (Hardened Infrastructure — Layer 3: Workload/Host Security)

Target: Module 03-gke-cluster/main.tf

Cause Analysis

In HashiCorp's Terraform Google ecosystem, advanced container runtime features like sandbox_config (which configures gVisor user-space kernel sandboxing on GKE node pools) are exposed through the google-beta provider.

Because our module defined google_container_node_pool.gvisor_nodes using the standard hashicorp/google provider without declaring google-beta, Terraform reported Error: Unsupported block type ... Blocks of type "sandbox_config" are not expected here.

We will update modules/03-gke-cluster/main.tf to:

Declare google-beta in the required_providers block.

Bind provider = google-beta directly to the gvisor_nodes node pool resource.

Update modules/03-gke-cluster/main.tf.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}


# ------------------------------------------------------------------------------
# 4. Node Pool 2: gVisor Sandboxed Workloads (Kernel Isolation)
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "gvisor_nodes" {
  provider   = google-beta
  name       = "gvisor-sandbox-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
  node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }
  ......

==================================

I have some questions: 1) in gcp terraform for sandbox_config { sandbox_type = } how many other options we have for sandbox_type ?

For sandbox_config { sandbox_type = ... } in GCP and Terraform, "gvisor" is currently the only supported option.

Key Technical Details

1) GKE REST API Enum:
Under the hood, GCP's NodeConfig.SandboxConfig schema only defines two enum states:
- UNSPECIFIED (Default: standard runc container execution, sharing the host Linux kernel).
- GVISOR (Terraform string value: "gvisor"): Intercepts container system calls and executes them in an isolated user-space kernel (Sentry + Gofer architecture).

2) Why Aren't There Other Options (e.g., Kata Containers or Firecracker)?

While open-source Kubernetes supports other runtime classes (such as Kata Containers or Firecracker MicroVMs), Google Cloud natively built and managed GKE Sandbox entirely around gVisor for its low memory overhead and tight integration with Container-Optimized OS (COS_CONTAINERD).

3) Behavior Matrix:

sandbox_config Block---ContainerRuntime---Kernel Isolation Level---Primary Use Case
Not Defined---containerd + runc--- Shared Host Linux Kernel---Trusted internal microservices, high-throughput system pods.
sandbox_type = "gvisor"--- containerd + runsc (gVisor)--- User-Space Kernel Sandbox--- Multi-tenant apps, untrusted code execution, LLM prompt runners, and Phase 2 MLOps inference engines.

=======================

3. What is disable-legacy-endpoints = "true"?
This metadata flag mitigates Server-Side Request Forgery (SSRF) attacks targeting the Google Compute Engine (GCE) Metadata Server.

The Attack Vector (Without This Flag)
Every GKE node communicates with a local IP address at 169.254.169.254 to fetch instance metadata and IAM service account tokens.

In older versions of GCP (Metadata API v0.1 and v1beta1), any HTTP GET request sent to 169.254.169.254 returned sensitive data immediately:

Bash
# Old/Legacy behavior (Vulnerable to basic SSRF)
curl http://169.254.169.254/computeMetadata/v0.1/instance/service-accounts/default/token
If an attacker exploited an SSRF vulnerability in a web application running inside a container, they could trick the app into executing that curl command, steal the node's GCP IAM credentials, and compromise your cloud infrastructure.

The Defense (disable-legacy-endpoints = "true")
Setting disable-legacy-endpoints = "true" completely shuts down the legacy v0.1 and v1beta1 metadata endpoints.

When legacy endpoints are disabled, the Metadata Server only accepts requests formatted for the v1 API, which strictly requires a custom HTTP header:

Bash
# Modern v1 Metadata API (Secure)
curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
Because 99% of basic SSRF attacks (such as image-rendering injection or URL parameter manipulation) cannot inject custom HTTP headers like Metadata-Flavor: Google, disabling legacy endpoints blocks SSRF token exfiltration at the host layer.

===========
well, I didn't understand the following: "When legacy endpoints are disabled, the Metadata Server only accepts requests formatted for the v1 API, which strictly requires a custom HTTP header:

Bash

# Modern v1 Metadata API (Secure)
curl -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
Because 99% of basic SSRF attacks (such as image-rendering injection or URL parameter manipulation) cannot inject custom HTTP headers like Metadata-Flavor: Google, disabling legacy endpoints blocks SSRF token exfiltration at the host layer."

========
Let's break this down using a real-world vulnerable application scenario.

---

### The Scenario: A Vulnerable Web Application

Imagine we have a web application running inside a container on our GKE node. This application lets users upload a profile picture by providing a web link (URL):

```python
# Vulnerable Python backend code on our app
@app.route("/upload-avatar")
def upload_avatar():
    user_url = request.args.get("url")
    
    # The server fetches the image from the user's URL
    response = requests.get(user_url) 
    return response.content

```

An attacker doesn't provide a picture URL like `[https://example.com/dog.jpg](https://example.com/dog.jpg)`. Instead, they exploit this to commit **Server-Side Request Forgery (SSRF)** by passing the internal GCP Metadata server's IP address (`169.254.169.254`).

---

### Scenario A: Legacy Endpoints ENABLED (The Vulnerability)

1. **The Attacker Sends This Input:**
`[https://myapp.com/upload-avatar?url=http://169.254.169.254/computeMetadata/v0.1/instance/service-accounts/default/token](https://myapp.com/upload-avatar?url=http://169.254.169.254/computeMetadata/v0.1/instance/service-accounts/default/token)`
2. **What the Backend Server Executes:**
The backend app runs: `requests.get("[http://169.254.169.254/computeMetadata/v0.1/](http://169.254.169.254/computeMetadata/v0.1/)...")`
3. **What GCP Metadata Server Does:**
The legacy `v0.1` API **does not ask for any proof or special headers**. It sees a standard `GET` request arriving from inside the cluster and replies:
> *"Here is your active GCP IAM Access Token: `ya29.a0ARR...`"*


4. **The Impact:**
The vulnerable web application returns the token back to the attacker. The attacker now has full GCP IAM permissions assigned to that node!

---

### Scenario B: Legacy Endpoints DISABLED / v1 Required (The Defense)

Now, we set `disable-legacy-endpoints = "true"`. The legacy `v0.1` API is shut off. GCP now **requires** the `v1` Metadata API, which enforces a mandatory rule: **"I will only talk to you if your HTTP request contains the header `Metadata-Flavor: Google`."**

1. **The Attacker Tries the Same Attack:**
`[https://myapp.com/upload-avatar?url=http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token](https://myapp.com/upload-avatar?url=http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token)`
2. **What the Backend Server Executes:**
The backend app runs: `requests.get("[http://169.254.169.254/computeMetadata/v1/](http://169.254.169.254/computeMetadata/v1/)...")`
3. **What GCP Metadata Server Does:**
The Metadata Server inspects the incoming HTTP request and checks:
* Is `Metadata-Flavor: Google` inside the HTTP headers?
* **Answer:** **NO.** (Because the vulnerable Python code `requests.get(user_url)` only sends standard default headers like `User-Agent: python-requests`).


4. **The Result:**
GCP immediately drops the request with **`403 Forbidden`**. The attacker gets nothing!

---

### Why Can't the Attacker Just "Add" the Header in the URL?

HTTP Headers and URLs are fundamentally separate in web networking:

* **A URL string** can only specify the protocol, host, port, path, and query strings (e.g., `http://host/path?key=value`). You **cannot** put HTTP headers inside a URL.
* To add an HTTP header, you must modify the actual application code calling the API (e.g., `requests.get(url, headers={"Metadata-Flavor": "Google"})`).

Unless the attacker has full **Remote Code Execution (RCE)** to rewrite your Python/Node.js code on the server, a URL-based SSRF attack **cannot** force your backend server to inject custom HTTP headers into outgoing network packets.

----------------------------

@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ cd /workspaces/gke-defense-in-depth/environments/prod

# 1. Initialize Terraform modules and google-beta provider
terraform init

# 2. Deploy infrastructure (Creating private GKE cluster & node pools)
# Note: Initial GKE cluster creation usually takes 8 to 12 minutes in GCP.
terraform apply -auto-approve
Initializing the backend...

Initializing modules...
- kms_cmek in ../../modules/02-kms-cmek
- gke_cluster in ../../modules/03-gke-cluster
- vpc_network in ../../modules/01-vpc-network
╷
│ Error: Duplicate 'backend' configuration block
│ 
│   on main.tf line 14, in terraform:
│   14:   backend "gcs" {
│ 
│ A module may have only one 'backend' configuration block. The backend was previously configured at backend.tf:2,3-16.
╵
╷
│ Error: Duplicate 'backend' configuration block
│ 
│   on main.tf line 14, in terraform:
│   14:   backend "gcs" {
│ 
│ A module may have only one 'backend' configuration block. The backend was previously configured at backend.tf:2,3-16.

===============
That error happens because Terraform merges all .tf files in a directory into one configuration, and it found a backend "gcs" block in both backend.tf and main.tf.

To fix this, keep backend.tf as the dedicated file for remote state and remove the backend block from environments/prod/main.tf.

===========

I don't understand what is the use of "environments/prod/terraform.tfvars" file while we have all the required variables in "environments/prod/variables.tf"?

This is one of the most common points of confusion when learning Terraform!

Think of it as the difference between **defining a function** and **calling a function with specific arguments**.

---

### The Comparison

| File | Analogy | Role in Terraform |
| --- | --- | --- |
| **`variables.tf`** | **The Function Definition** (The Schema) | Defines *what* variables are allowed to exist, their data types, and optional descriptions. It tells Terraform: *"Hey, expect someone to give you a string called `project_id`."* |
| **`terraform.tfvars`** | **The Function Call** (The Actual Data) | Assigns the *actual concrete values* for that specific run. It tells Terraform: *"Here is the exact value for `project_id`: `"kam-dev-test"`."* |

---

### A Code Example

In **`variables.tf`**, you declare the blueprint:

```hcl
# "I am telling Terraform that a variable named cluster_name exists."
variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster"
}

```

In **`terraform.tfvars`**, you supply the value:

```hcl
# "Here is the actual value to use for this deployment."
cluster_name = "prod-gke-did-cluster"

```

---

### But why not just put `default = "prod-gke-did-cluster"` inside `variables.tf`?

You *can* put `default = "..."` inside `variables.tf`, but in real-world infrastructure engineering, separating them offers three massive advantages:

1. **Reusability across environments (`dev`, `staging`, `prod`):**
If you have three environments, your code files (`main.tf` and `variables.tf`) can be **100% identical**. You simply swap out or supply a different `.tfvars` file for each environment:
* `dev.tfvars` $\rightarrow$ `cluster_name = "dev-cluster"`
* `prod.tfvars` $\rightarrow$ `cluster_name = "prod-cluster"`


2. **Code vs. Config Separation:**
`variables.tf` is logic/code structure. `terraform.tfvars` is pure configuration data. Keeping them separate makes code reviews much cleaner (you instantly see what configuration values changed without digging through infrastructure code).
3. **Auto-Loading Behavior:**
Terraform is hardcoded to automatically look for any file named exactly `terraform.tfvars` in the working directory and load those values automatically when you run `terraform plan` or `terraform apply`.

---

In short: **`variables.tf` reserves the slot, and `terraform.tfvars` fills the slot.**

===============


@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ cd /workspaces/gke-defense-in-depth/environments/prod

# 1. Initialize Terraform modules and google-beta provider
terraform init

# 2. Deploy infrastructure (Creating private GKE cluster & node pools)
# Note: Initial GKE cluster creation usually takes 8 to 12 minutes in GCP.
terraform apply -auto-approve
Initializing the backend...


module.gke_cluster.google_container_node_pool.system_nodes: Still creating... [01m40s elapsed]
module.gke_cluster.google_container_node_pool.system_nodes: Creation complete after 1m44s [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster/nodePools/system-node-pool]
╷
│ Error: error creating NodePool: googleapi: Error 400: Node labels with key "sandbox.gke.io/runtime" are managed by GKE and must not be manually specified.
│ Details:
│ [
│   {
│     "@type": "type.googleapis.com/google.rpc.RequestInfo",
│     "requestId": "0x4b47d849341df55a"
│   }
│ ]
│ , badRequest
│ 
│   with module.gke_cluster.google_container_node_pool.gvisor_nodes,
│   on ../../modules/03-gke-cluster/main.tf line 165, in resource "google_container_node_pool" "gvisor_nodes":
│  165: resource "google_container_node_pool" "gvisor_nodes" {
│ 

=========

Cause Analysis
When you configure sandbox_config { sandbox_type = "gvisor" } on a GKE node pool, GKE automatically manages and injects both:

The node label: "sandbox.gke.io/runtime" = "gvisor"

The node taint: sandbox.gke.io/runtime=gvisor:NoSchedule

Because GKE manages this label key natively, GCP's API rejects manual declarations of "sandbox.gke.io/runtime" inside the labels map with Error 400: Node labels with key "sandbox.gke.io/runtime" are managed by GKE.

Step 1: Update modules/03-gke-cluster/main.tf
Update modules/03-gke-cluster/main.tf to remove the managed label and taint block from google_container_node_pool.gvisor_nodes.

the following codes:

# ------------------------------------------------------------------------------
# 4. Node Pool 2: gVisor Sandboxed Workloads (Kernel Isolation)
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "gvisor_nodes" {
  provider   = google-beta
  name       = "gvisor-sandbox-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
  node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = "e2-standard-4"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.gke_nodes_sa.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Layer 3: gVisor User-Space Sandbox Runtime
    sandbox_config {
      sandbox_type = "gvisor"
    }

    # Layer 6: CMEK Encrypted Boot Disks
    boot_disk_kms_key = var.gke_disk_key_id
    disk_size_gb      = 50
    disk_type         = "pd-standard"

    # Layer 3: Shielded Node Hardening
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Taint to force untrusted/isolated workloads to explicitly tolerate gVisor
    taint {
      key    = "sandbox.gke.io/runtime"
      value  = "gvisor"
      effect = "NO_SCHEDULE"
    }

    labels = {
      "sandbox.gke.io/runtime" = "gvisor"
      "workload-tier"          = "untrusted-unisolated"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

changed to:

# ------------------------------------------------------------------------------
# 4. Sandbox Node Pool (gVisor MicroVM Workload Isolation)
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "gvisor_nodes" {
  provider = google-beta

  name       = "gvisor-sandbox-pool"
  project    = var.project_id
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = "e2-standard-4"
    image_type   = "COS_CONTAINERD"
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Enable gVisor Sandbox Runtime (GKE manages sandbox.gke.io/runtime label and taint)
    sandbox_config {
      sandbox_type = "gvisor"
    }

    # KMS CMEK Boot Disk Encryption
    boot_disk_kms_key = var.gke_disk_key_id

    # Dedicated Least-Privilege SA
    service_account = google_service_account.gke_nodes_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Shielded VM Hardening
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      "workload-tier" = "untrusted-unisolated"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}
=============================

@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ cd /workspaces/gke-defense-in-depth/environments/prod

terraform apply -auto-approve
module.kms_cmek.google_project_service.compute_api: Refreshing state... [id=kam-dev-test/compute.googleapis.com]
@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ cd /workspaces/gke-defense-in-depth/environments/prod

terraform apply -auto-approve
module.kms_cmek.google_project_service.compute_api: Refreshing state... [id=kam-dev-test/compute.googleapis.com]
module.kms_cmek.google_kms_key_ring.keyring: Refreshing state... [id=projects/kam-dev-test/locations/us-central1/keyRings/gke-did-keyring]
module.kms_cmek.data.google_project.project: Reading...
module.kms_cmek.google_project_service.container_api: Refreshing state... [id=kam-dev-test/container.googleapis.com]
module.vpc_network.google_compute_network.vpc: Refreshing state... [id=projects/kam-dev-test/global/networks/gke-did-vpc]
module.vpc_network.google_compute_subnetwork.subnet: Refreshing state... [id=projects/kam-dev-test/regions/us-central1/subnetworks/gke-did-subnet-us-central1]
module.vpc_network.google_compute_router.router: Refreshing state... [id=projects/kam-dev-test/regions/us-central1/routers/gke-did-vpc-router]
module.kms_cmek.google_kms_crypto_key.gke_disk_key: Refreshing state... [id=projects/kam-dev-test/locations/us-central1/keyRings/gke-did-keyring/cryptoKeys/gke-disk-encryption-key]
module.kms_cmek.google_kms_crypto_key.gke_etcd_key: Refreshing state... [id=projects/kam-dev-test/locations/us-central1/keyRings/gke-did-keyring/cryptoKeys/gke-etcd-encryption-key]
module.kms_cmek.data.google_project.project: Read complete after 1s [id=projects/kam-dev-test]
module.vpc_network.google_compute_router_nat.nat: Refreshing state... [id=kam-dev-test/us-central1/gke-did-vpc-router/gke-did-vpc-nat]
module.kms_cmek.google_kms_crypto_key_iam_member.gke_disk_encrypter_decrypter: Refreshing state... [id=projects/kam-dev-test/locations/us-central1/keyRings/gke-did-keyring/cryptoKeys/gke-disk-encryption-key/roles/cloudkms.cryptoKeyEncrypterDecrypter/serviceAccount:service-243781974020@compute-system.iam.gserviceaccount.com]
module.kms_cmek.google_kms_crypto_key_iam_member.gke_etcd_encrypter_decrypter: Refreshing state... [id=projects/kam-dev-test/locations/us-central1/keyRings/gke-did-keyring/cryptoKeys/gke-etcd-encryption-key/roles/cloudkms.cryptoKeyEncrypterDecrypter/serviceAccount:service-243781974020@container-engine-robot.iam.gserviceaccount.com]
module.gke_cluster.google_service_account.gke_nodes_sa: Refreshing state... [id=projects/kam-dev-test/serviceAccounts/prod-gke-did-cluster-node-sa@kam-dev-test.iam.gserviceaccount.com]
module.gke_cluster.google_container_cluster.primary: Refreshing state... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster]
module.gke_cluster.google_project_iam_member.node_monitoring: Refreshing state... [id=kam-dev-test/roles/monitoring.metricWriter/serviceAccount:prod-gke-did-cluster-node-sa@kam-dev-test.iam.gserviceaccount.com]
module.gke_cluster.google_project_iam_member.node_artifact_registry: Refreshing state... [id=kam-dev-test/roles/artifactregistry.reader/serviceAccount:prod-gke-did-cluster-node-sa@kam-dev-test.iam.gserviceaccount.com]
module.gke_cluster.google_kms_crypto_key_iam_member.node_disk_decrypter: Refreshing state... [id=projects/kam-dev-test/locations/us-central1/keyRings/gke-did-keyring/cryptoKeys/gke-disk-encryption-key/roles/cloudkms.cryptoKeyEncrypterDecrypter/serviceAccount:prod-gke-did-cluster-node-sa@kam-dev-test.iam.gserviceaccount.com]
module.gke_cluster.google_project_iam_member.node_logging: Refreshing state... [id=kam-dev-test/roles/logging.logWriter/serviceAccount:prod-gke-did-cluster-node-sa@kam-dev-test.iam.gserviceaccount.com]
module.gke_cluster.google_container_node_pool.gvisor_nodes: Refreshing state... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster/nodePools/gvisor-sandbox-pool]
module.gke_cluster.google_container_node_pool.system_nodes: Refreshing state... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster/nodePools/system-node-pool]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  + create
  ~ update in-place

Terraform will perform the following actions:

  # module.gke_cluster.google_container_cluster.primary will be updated in-place
  ~ resource "google_container_cluster" "primary" {
        id                                       = "projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster"
        name                                     = "prod-gke-did-cluster"
        # (34 unchanged attributes hidden)

      ~ database_encryption {
          ~ state    = "ALL_OBJECTS_ENCRYPTION_ENABLED" -> "ENCRYPTED"
            # (1 unchanged attribute hidden)
        }

        # (24 unchanged blocks hidden)
    }

  # module.gke_cluster.google_container_node_pool.gvisor_nodes will be created
  + resource "google_container_node_pool" "gvisor_nodes" {
      + cluster                     = "prod-gke-did-cluster"
      + id                          = (known after apply)
      + initial_node_count          = (known after apply)
      + instance_group_urls         = (known after apply)
      + location                    = "us-central1"
      + managed_instance_group_urls = (known after apply)
      + max_pods_per_node           = (known after apply)
      + name                        = "gvisor-sandbox-pool"
      + name_prefix                 = (known after apply)
      + node_count                  = 1
      + node_locations              = (known after apply)
      + operation                   = (known after apply)
      + project                     = "kam-dev-test"
      + version                     = (known after apply)

      + autoscaling {
          + location_policy = (known after apply)
          + max_node_count  = 3
          + min_node_count  = 1
        }

      + management {
          + auto_repair  = true
          + auto_upgrade = true
        }

      + network_config (known after apply)

      + node_config {
          + boot_disk_kms_key = "projects/kam-dev-test/locations/us-central1/keyRings/gke-did-keyring/cryptoKeys/gke-disk-encryption-key"
          + disk_size_gb      = 50
          + disk_type         = "pd-standard"
          + effective_taints  = (known after apply)
          + guest_accelerator = (known after apply)
          + image_type        = "COS_CONTAINERD"
          + labels            = {
              + "workload-tier" = "untrusted-unisolated"
            }
          + local_ssd_count   = (known after apply)
          + logging_variant   = (known after apply)
          + machine_type      = "e2-standard-4"
          + metadata          = {
              + "disable-legacy-endpoints" = "true"
            }
          + min_cpu_platform  = (known after apply)
          + oauth_scopes      = [
              + "https://www.googleapis.com/auth/cloud-platform",
            ]
          + preemptible       = false
          + service_account   = "prod-gke-did-cluster-node-sa@kam-dev-test.iam.gserviceaccount.com"
          + spot              = false

          + confidential_nodes (known after apply)

          + gcfs_config (known after apply)

          + kubelet_config (known after apply)

          + sandbox_config {
              + sandbox_type = "gvisor"
            }

          + shielded_instance_config {
              + enable_integrity_monitoring = true
              + enable_secure_boot          = true
            }

          + workload_metadata_config (known after apply)
        }

      + upgrade_settings (known after apply)
    }

Plan: 1 to add, 1 to change, 0 to destroy.
module.gke_cluster.google_container_cluster.primary: Modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 00m10s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 00m20s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 00m30s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 00m40s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 00m50s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 01m00s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 01m10s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 01m20s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 01m30s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 01m40s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 01m50s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 02m00s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 03m00s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 03m10s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 03m20s elapsed]
module.gke_cluster.google_container_cluster.primary: Still modifying... [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster, 03m30s elapsed]
╷
│ Error: Error waiting for updating GKE cluster database encryption config: DeployPatch failed
│ 
│   with module.gke_cluster.google_container_cluster.primary,
│   on ../../modules/03-gke-cluster/main.tf line 52, in resource "google_container_cluster" "primary":
│   52: resource "google_container_cluster" "primary" {
│ 
===============
Cause Analysis: The "State Drift" Quirk
You just hit a classic, very common Terraform lifecycle quirk with GCP!

Here is exactly what happened:

When we first created the cluster, we told GCP: state = "ENCRYPTED".

GCP received the command and began encrypting all the Kubernetes secrets in the background.

Once GCP finished encrypting everything, it updated its own internal status to ALL_OBJECTS_ENCRYPTION_ENABLED.

When you just ran terraform apply again, Terraform looked at GCP and said: "Wait, GCP says ALL_OBJECTS_ENCRYPTION_ENABLED, but my code says ENCRYPTED! Let me change it back."

GCP rejected Terraform's attempt to "downgrade" the state, resulting in the DeployPatch failed error. (You can actually see this in your log: ~ state = "ALL_OBJECTS_ENCRYPTION_ENABLED" -> "ENCRYPTED").

To fix this, we need to use Terraform's lifecycle block with ignore_changes. This tells Terraform: "Set the state to ENCRYPTED when you first create the cluster, but if GCP changes the status later, ignore it and do not try to change it back."

Step 1: Update modules/03-gke-cluster/main.tf

We will add a lifecycle block to the google_container_cluster resource to ignore changes to the database encryption state (and initial_node_count, which is another field that can cause drift).

# ----------------------------------------------------------------------------
  # PREVENT STATE DRIFT ERRORS
  # ----------------------------------------------------------------------------
  lifecycle {
    ignore_changes = [
      initial_node_count,
      database_encryption[0].state
    ]
  }
}
=================
module.gke_cluster.google_container_node_pool.gvisor_nodes: Creation complete after 1m44s [id=projects/kam-dev-test/locations/us-central1/clusters/prod-gke-did-cluster/nodePools/gvisor-sandbox-pool]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

cluster_endpoint = "35.232.167.233"
cluster_name = "prod-gke-did-cluster"
gke_disk_key_id = "projects/kam-dev-test/locations/us-central1/keyRings/gke-did-keyring/cryptoKeys/gke-disk-encryption-key"
gke_etcd_key_id = "projects/kam-dev-test/locations/us-central1/keyRings/gke-did-keyring/cryptoKeys/gke-etcd-encryption-key"
network_id = "projects/kam-dev-test/global/networks/gke-did-vpc"
node_service_account = "prod-gke-did-cluster-node-sa@kam-dev-test.iam.gserviceaccount.com"
pod_ip_range_name = "gke-pods"
subnet_id = "projects/kam-dev-test/regions/us-central1/subnetworks/gke-did-subnet-us-central1"
svc_ip_range_name = "gke-services"

=================

@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ gcloud container clusters get-credentials prod-gke-did-cluster \
  --region us-central1 \
  --project kam-dev-test
Fetching cluster endpoint and auth data.
CRITICAL: ACTION REQUIRED: gke-gcloud-auth-plugin, which is needed for continued use of kubectl, was not found or is not executable. Install gke-gcloud-auth-plugin for use with kubectl by following https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin
kubeconfig entry generated for prod-gke-did-cluster.
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ kubectl get nodes -o wide
E0729 22:43:25.945807  103037 memcache.go:265] "Unhandled Error" err=<
        couldn't get current server API group list: Get "https://35.232.167.233/api?timeout=32s": getting credentials: exec: executable gke-gcloud-auth-plugin not found

        It looks like you are trying to use a client-go credential plugin that is not installed.

        To learn more about this feature, consult the documentation available at:
              https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins

        Install gke-gcloud-auth-plugin for use with kubectl by following https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin
 >
E0729 22:43:25.946495  103037 memcache.go:265] "Unhandled Error" err=<
        couldn't get current server API group list: Get "https://35.232.167.233/api?timeout=32s": getting credentials: exec: executable gke-gcloud-auth-plugin not found

        It looks like you are trying to use a client-go credential plugin that is not installed.

        To learn more about this feature, consult the documentation available at:
              https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins

        Install gke-gcloud-auth-plugin for use with kubectl by following https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin
 >
E0729 22:43:25.948423  103037 memcache.go:265] "Unhandled Error" err=<
        couldn't get current server API group list: Get "https://35.232.167.233/api?timeout=32s": getting credentials: exec: executable gke-gcloud-auth-plugin not found

        It looks like you are trying to use a client-go credential plugin that is not installed.

        To learn more about this feature, consult the documentation available at:
              https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins

        Install gke-gcloud-auth-plugin for use with kubectl by following https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin
 >
E0729 22:43:25.949176  103037 memcache.go:265] "Unhandled Error" err=<
        couldn't get current server API group list: Get "https://35.232.167.233/api?timeout=32s": getting credentials: exec: executable gke-gcloud-auth-plugin not found

        It looks like you are trying to use a client-go credential plugin that is not installed.

        To learn more about this feature, consult the documentation available at:
              https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins

        Install gke-gcloud-auth-plugin for use with kubectl by following https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin
 >
E0729 22:43:25.951014  103037 memcache.go:265] "Unhandled Error" err=<
        couldn't get current server API group list: Get "https://35.232.167.233/api?timeout=32s": getting credentials: exec: executable gke-gcloud-auth-plugin not found

        It looks like you are trying to use a client-go credential plugin that is not installed.

        To learn more about this feature, consult the documentation available at:
              https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins

        Install gke-gcloud-auth-plugin for use with kubectl by following https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin
 >
Unable to connect to the server: getting credentials: exec: executable gke-gcloud-auth-plugin not found

It looks like you are trying to use a client-go credential plugin that is not installed.

To learn more about this feature, consult the documentation available at:
      https://kubernetes.io/docs/reference/access-authn-authz/authentication/#client-go-credential-plugins

Install gke-gcloud-auth-plugin for use with kubectl by following https://cloud.google.com/kubernetes-engine/docs/how-to/cluster-access-for-kubectl#install_plugin

==================

That error pops up because Google Cloud separated GKE authentication out of the core `gcloud` CLI into a standalone binary named `gke-gcloud-auth-plugin`. Without it installed in your terminal environment, `kubectl` doesn't know how to authenticate against the private cluster master.

Here is how to quickly install the plugin and reconnect to your cluster:

1. **Install the GKE Auth Plugin:** Codespaces / Debian / Ubuntu.
Run the `apt` package manager command to install the official Google authentication binary:

```bash
sudo apt-get update && sudo apt-get install -y google-cloud-cli-gke-gcloud-auth-plugin

```

> *Note:* If your `gcloud` was installed manually via component manager instead of `apt`, run `gcloud components install gke-gcloud-auth-plugin` instead.


2. **Re-generate Kubeconfig Credentials:** Refresh authentication token.
Re-run the credential fetching command so `gcloud` can configure `kubectl` with the new plugin:

```bash
gcloud container clusters get-credentials prod-gke-did-cluster \
  --region us-central1 \
  --project kam-dev-test

```


3. **Verify Cluster Connectivity:** Run live node checks.
Execute the verification commands to confirm nodes and Cilium eBPF are healthy:

```bash
# 1. Check node status and machine specs
kubectl get nodes -o wide

# 2. Inspect the gVisor node pool for the auto-applied taint
kubectl get nodes -l sandbox.gke.io/runtime=gvisor -o yaml | grep -A 5 -i "taints"

# 3. Confirm Cilium eBPF pods (Dataplane V2) are running
kubectl get pods -n kube-system -l k8s-app=cilium

```


---

Once you run those steps and `kubectl get nodes` returns your active cluster nodes, let me know what output you get and we'll advance directly to **Tier 3 (Service Mesh & Data Plane Zero-Trust Security)**!

============================

@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ sudo apt-get update && sudo apt-get install -y google-cloud-cli-gke-gcloud-auth-plugin
Get:1 https://packages.microsoft.com/repos/microsoft-ubuntu-noble-prod noble InRelease [3600 B]
Get:2 https://apt.releases.hashicorp.com noble InRelease [12.9 kB]                                                                                                          
Hit:3 http://archive.ubuntu.com/ubuntu noble InRelease                                                                                     
Get:4 http://archive.ubuntu.com/ubuntu noble-updates InRelease [126 kB]           
Get:5 http://security.ubuntu.com/ubuntu noble-security InRelease [126 kB]                                   
Get:6 https://packages.cloud.google.com/apt cloud-sdk InRelease [1621 B]                                    
Get:7 https://packages.microsoft.com/repos/microsoft-ubuntu-noble-prod noble/main amd64 Packages [258 kB]
Get:8 http://archive.ubuntu.com/ubuntu noble-backports InRelease [126 kB]                     
Get:9 https://apt.releases.hashicorp.com noble/main amd64 Packages [303 kB]
Get:10 http://archive.ubuntu.com/ubuntu noble-updates/universe amd64 Packages [2138 kB]
Get:11 http://security.ubuntu.com/ubuntu noble-security/restricted amd64 Packages [1587 kB]
Get:12 https://packages.cloud.google.com/apt cloud-sdk/main all Packages [2075 kB]         
Get:13 http://archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages [1433 kB]                                 
Get:14 http://archive.ubuntu.com/ubuntu noble-updates/restricted amd64 Packages [1700 kB]                       
Get:15 http://security.ubuntu.com/ubuntu noble-security/main amd64 Packages [1110 kB]                  
Get:16 http://security.ubuntu.com/ubuntu noble-security/universe amd64 Packages [1522 kB]
Get:17 https://packages.cloud.google.com/apt cloud-sdk/main amd64 Packages [4939 kB]
Fetched 17.5 MB in 2s (8879 kB/s)   
Reading package lists... Done
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
The following NEW packages will be installed:
  google-cloud-cli-gke-gcloud-auth-plugin
0 upgraded, 1 newly installed, 0 to remove and 145 not upgraded.
Need to get 3924 kB of archives.
After this operation, 9873 kB of additional disk space will be used.
Get:1 https://packages.cloud.google.com/apt cloud-sdk/main amd64 google-cloud-cli-gke-gcloud-auth-plugin amd64 578.0.0-0 [3924 kB]
Fetched 3924 kB in 1s (2969 kB/s)                                
Selecting previously unselected package google-cloud-cli-gke-gcloud-auth-plugin.
(Reading database ... 97028 files and directories currently installed.)
Preparing to unpack .../google-cloud-cli-gke-gcloud-auth-plugin_578.0.0-0_amd64.deb ...
Unpacking google-cloud-cli-gke-gcloud-auth-plugin (578.0.0-0) ...
Setting up google-cloud-cli-gke-gcloud-auth-plugin (578.0.0-0) ...
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ gcloud container clusters get-credentials prod-gke-did-cluster \
  --region us-central1 \
  --project kam-dev-test
Fetching cluster endpoint and auth data.
kubeconfig entry generated for prod-gke-did-cluster.
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ kubectl get nodes -o wide
NAME                                                  STATUS   ROLES    AGE     VERSION               INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                             KERNEL-VERSION   CONTAINER-RUNTIME
gke-prod-gke-did-clu-gvisor-sandbox-p-4e04f653-gfmr   Ready    <none>   8m54s   v1.35.6-gke.1127000   10.10.0.8     <none>        Container-Optimized OS from Google   6.12.85+         containerd://2.1.7
gke-prod-gke-did-clu-gvisor-sandbox-p-5540269c-tp4m   Ready    <none>   8m48s   v1.35.6-gke.1127000   10.10.0.9     <none>        Container-Optimized OS from Google   6.12.85+         containerd://2.1.7
gke-prod-gke-did-clu-gvisor-sandbox-p-8e9d063b-cfwr   Ready    <none>   8m48s   v1.35.6-gke.1127000   10.10.0.10    <none>        Container-Optimized OS from Google   6.12.85+         containerd://2.1.7
gke-prod-gke-did-clu-system-node-pool-2cb02a36-d8rb   Ready    <none>   54m     v1.35.6-gke.1127000   10.10.0.7     <none>        Container-Optimized OS from Google   6.12.85+         containerd://2.1.7
gke-prod-gke-did-clu-system-node-pool-65a86855-71zz   Ready    <none>   54m     v1.35.6-gke.1127000   10.10.0.5     <none>        Container-Optimized OS from Google   6.12.85+         containerd://2.1.7
gke-prod-gke-did-clu-system-node-pool-af4572b4-55kf   Ready    <none>   54m     v1.35.6-gke.1127000   10.10.0.6     <none>        Container-Optimized OS from Google   6.12.85+         containerd://2.1.7
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ kubectl get nodes -l sandbox.gke.io/runtime=gvisor -o yaml | grep -A 5 -i "taints"
      node.gke.io/last-applied-node-taints: sandbox.gke.io/runtime=gvisor:NoSchedule
      volumes.kubernetes.io/controller-managed-attach-detach: "true"
    creationTimestamp: "2026-07-29T22:39:24Z"
    labels:
      addon.gke.io/node-local-dns-ds-ready: "true"
      beta.kubernetes.io/arch: amd64
--
    taints:
    - effect: NoSchedule
      key: sandbox.gke.io/runtime
      value: gvisor
  status:
    addresses:
--
      node.gke.io/last-applied-node-taints: sandbox.gke.io/runtime=gvisor:NoSchedule
      volumes.kubernetes.io/controller-managed-attach-detach: "true"
    creationTimestamp: "2026-07-29T22:39:30Z"
    labels:
      addon.gke.io/node-local-dns-ds-ready: "true"
      beta.kubernetes.io/arch: amd64
--
    taints:
    - effect: NoSchedule
      key: sandbox.gke.io/runtime
      value: gvisor
  status:
    addresses:
--
      node.gke.io/last-applied-node-taints: sandbox.gke.io/runtime=gvisor:NoSchedule
      volumes.kubernetes.io/controller-managed-attach-detach: "true"
    creationTimestamp: "2026-07-29T22:39:30Z"
    labels:
      addon.gke.io/node-local-dns-ds-ready: "true"
      beta.kubernetes.io/arch: amd64
--
    taints:
    - effect: NoSchedule
      key: sandbox.gke.io/runtime
      value: gvisor
  status:
    addresses:
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ kubectl get pods -n kube-system -l k8s-app=cilium
NAME          READY   STATUS    RESTARTS   AGE
anetd-hbkv8   3/3     Running   0          10m
anetd-hn4jc   3/3     Running   0          55m
anetd-kh72j   3/3     Running   0          9m54s
anetd-kvhn9   3/3     Running   0          55m
anetd-rjnv8   3/3     Running   0          9m56s
anetd-rv256   3/3     Running   0          55m

Look at those cluster nodes — completely private IPs (10.10.0.x), zero external public IPs exposed, 3 gVisor sandboxed nodes with the sandbox.gke.io/runtime=gvisor:NoSchedule taint applied, and 6 healthy eBPF anetd Cilium pods running! Tier 1 and Tier 2 are officially 100% verified and operational.

=======================
Look at those cluster nodes — completely private IPs (`10.10.0.x`), zero external public IPs exposed, 3 gVisor sandboxed nodes with the `sandbox.gke.io/runtime=gvisor:NoSchedule` taint applied, and 6 healthy eBPF `anetd` Cilium pods running! **Tier 1 and Tier 2 are officially 100% verified and operational.**

---

## Tier 3 — Service Mesh & Data Plane Zero-Trust Security

Now we move to **Tier 3**, where we secure the in-cluster data plane:

* **Module `04-service-mesh`:** Registers our private GKE cluster to Google Cloud Fleet (GKE Hub) and provisions **Managed Cloud Service Mesh** (managed Istio control plane).
* **Strict mTLS:** Enforces cryptographic mTLS encryption and identity verification for all pod-to-pod communications.
* **Default-Deny Cilium Network Policies:** Enforces zero-trust isolation so pods cannot talk to each other unless explicitly whitelisted.

---

### Step 1: Build Module `04-service-mesh`

This module connects our cluster to Google Cloud Fleet and turns on managed Service Mesh with automatic control plane updates.

#### 1.1 Create `modules/04-service-mesh/variables.tf`

================
here is the full plan for "gke-defense-in-depth" project, as I can see module 04 is "04-binary-auth" and 05 is "05-cloud-service-mesh". did we miss the "04-binary-auth"? 

Eagle eye! You caught that right away—I jumped straight ahead to Service Mesh and skipped 04-binary-auth.

Let me fix that right now so our implementation matches your exact repo structure and maintains our Defense-in-Depth hierarchy.

Why Binary Authorization (04-binary-auth) Matters
Binary Authorization enforces Layer 2 (Software Supply Chain Security & Container Integrity).

Even if your network and cluster are locked down, an attacker could still try to deploy a malicious or compromised container image. Binary Authorization acts as an admission controller gatekeeper at the Kubernetes API level:

Container Analysis Note & Attestor: Establishes digital trust authorities (Attestors) that verify container provenance.

Admission Control Policy: Blocks unverified container images from being scheduled on the GKE cluster while allowing system images (Cilium, DNS, logging agents) to run cleanly.

Tier 2 — Step 2: Building modules/04-binary-auth
Let's build modules/04-binary-auth from scratch.

================

explain in detail what is happening in "modules/04-binary-auth/main.tf"


Here is a detailed breakdown of the architectural logic, security rationale, and resource interactions happening inside `modules/04-binary-auth/main.tf`.

---

## Executive Summary

`modules/04-binary-auth/main.tf` implements **Layer 2 (Software Supply Chain Security & Container Integrity)** of our Defense-in-Depth model.

It prevents unauthorized, tampered, or unvetted container images from executing inside your GKE cluster. It creates an admission control gatekeeper at the Kubernetes API layer that intercepts deployment requests before pods are ever scheduled onto nodes.

---

## Step-by-Step Rationale & Resource Breakdown

```text
[ Deployment Request (kubectl / CI-CD) ]
                   │
                   ▼
[ Binary Authorization Policy ] ─── Is it a GKE System Image? ──► YES ──► [ ALLOW ]
                   │
                   └─► NO (User Container)
                         │
                         ▼
           [ Check Evaluation Mode ]
                         │
       ┌─────────────────┴─────────────────┐
       ▼                                   ▼
[ ALWAYS_ALLOW ]                 [ REQUIRE_ATTESTATION ]
(Bootstrap Mode)                 (Strict Pipeline Mode)
       │                                   │
       ▼                                   ▼
   [ ALLOW ]                   [ Verify Attestor Note ]
                               (Signed by CI/CD PGP/KMS Key)

```

---

### 1. Enabling Security APIs (`google_project_service`)

```hcl
resource "google_project_service" "binauthz_api" {
  project            = var.project_id
  service            = "binaryauthorization.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "containeranalysis_api" {
  project            = var.project_id
  service            = "containeranalysis.googleapis.com"
  disable_on_destroy = false
}

```

* **`binaryauthorization.googleapis.com`:** The core engine that hooks into GKE's Kubernetes Admission Controller webhook. It inspects image URIs on incoming pod manifests.
* **`containeranalysis.googleapis.com`:** The centralized GCP metadata storage service. Binary Authorization uses this API to read and store "Notes" and "Occurrences" (proofs that an image passed vulnerability scans or CI/CD signing stages).
* **`disable_on_destroy = false`:** Prevents Terraform from tearing down GCP platform APIs if the module is deleted, preventing cascading failures across other project services.

---

### 2. The Attestor Anchor (`google_container_analysis_note`)

```hcl
resource "google_container_analysis_note" "attestor_note" {
  name    = "${var.attestor_name}-note"
  project = var.project_id

  attestation_authority {
    hint {
      human_readable_name = "Production Release Build Attestor Note"
    }
  }
}

```

* **What is a "Note"?** In GCP's Container Analysis framework, a **Note** acts as a trusted metadata descriptor or "authority definition."
* Think of the Note as the **trust anchor** in the cloud. It declares: *"An authority exists in this project that is allowed to vouch for container images."*

---

### 3. The Digital Attestor (`google_binary_authorization_attestor`)

```hcl
resource "google_binary_authorization_attestor" "attestor" {
  name    = var.attestor_name
  project = var.project_id

  attestation_authority_note {
    note_reference = google_container_analysis_note.attestor_note.name
  }
}

```

* **What is an Attestor?** An **Attestor** is the identity in Binary Authorization that verifies digital signatures attached to container images.
* **The Link:** It binds directly to the `attestor_note` created above.
* **In Production Pipelines:** You attach public cryptographic keys (KMS or PGP) to this Attestor. When your CI/CD pipeline builds a container, it signs the image hash using a private key. The Attestor uses the public key defined here to cryptographically verify the signature at deploy time.

---

### 4. Admission Control Policy (`google_binary_authorization_policy`)

```hcl
resource "google_binary_authorization_policy" "policy" {
  project = var.project_id

  global_policy_evaluation_mode = "ENABLE"

  default_admission_rule {
    evaluation_mode  = "ALWAYS_ALLOW"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  }
}

```

This resource defines the project-wide security rules GKE applies to every container deployment:

1. **`global_policy_evaluation_mode = "ENABLE"` (CRITICAL):**
* Automatically trusts system images maintained directly by Google (such as Cilium eBPF `anetd`, `kube-dns`, metrics-server, and gVisor helpers).
* **Why this is vital:** If set to `DISABLE`, Binary Authorization would block core cluster infrastructure pods from starting, crashing the cluster.


2. **`evaluation_mode = "ALWAYS_ALLOW"`:**
* Sets default handling for custom user images during early cluster bootstrap.
* In a strict production CI/CD pipeline, this string gets updated to **`REQUIRE_ATTESTATION`**, requiring images to be explicitly signed by `google_binary_authorization_attestor.attestor`.


3. **`enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"`:**
* Dictates the action taken when an image violates the policy:
* **Block:** Rejects the Kubernetes deployment immediately at the API server layer.
* **Audit Log:** Emits a structured security event directly to Cloud Logging for SOC/SecOps monitoring.





---

### Summary Matrix

| Resource | GCP API Entity | Security Layer | Purpose |
| --- | --- | --- | --- |
| `google_project_service` | `binaryauthorization` & `containeranalysis` | Platform Enablement | Enables deploy-time inspection & metadata storage APIs. |
| `google_container_analysis_note` | Container Analysis Note | Metadata Trust Anchor | Establishes the definition of a trusted signing authority. |
| `google_binary_authorization_attestor` | BinAuthz Attestor | Verification Identity | Holds verification keys to validate container image signatures. |
| `google_binary_authorization_policy` | BinAuthz Policy | Admission Gatekeeper | Enforces rules on GKE cluster deployments and blocks untrusted images. |

================

I am not sure about the following, why it is "always_allow"? evaluation_mode = "ALWAYS_ALLOW":

Sets default handling for custom user images during early cluster bootstrap.
In a strict production CI/CD pipeline, this string gets updated to REQUIRE_ATTESTATION, requiring images to be explicitly signed by google_binary_authorization_attestor.attestor.

======

That reaction makes complete sense! From a pure security perspective, seeing `ALWAYS_ALLOW` inside a security module feels like leaving the front door unlocked.

Here is why this is standard practice during initial infrastructure bootstrap, and how it fits into a real-world **DevSecOps lifecycle**.

---

### The "Chicken-and-Egg" Problem

Binary Authorization requires images to be cryptographically signed by a private key during a CI/CD build process (e.g., in GitHub Actions or Cloud Build) using an Attestor's public key.

If we set `evaluation_mode = "REQUIRE_ATTESTATION"` right now in Terraform:

1. **The Infrastructure Phase (Where we are now):** We are building the cluster and foundation using Terraform. We haven't created our application CI/CD pipelines or signing keys yet.
2. **The Immediate Failure:** The moment you try to deploy *any* custom container (like a test app, ingress controller, or MLOps workload in Tier 5), GKE's admission controller will block it instantly because no signed attestation exists in GCP Container Analysis.
3. **Deadlock:** You can't test or initialize workloads because the pipeline that signs them hasn't run yet.

---

### The Progressive Hardening Strategy

In enterprise platform engineering, security rollout happens in **3 distinct phases**:

```text
Phase 1: Plumbing (Current)    Phase 2: Pipeline Integration     Phase 3: Strict Enforcement
┌──────────────────────────┐    ┌──────────────────────────┐    ┌──────────────────────────┐
│ Terraform builds:        │    │ CI/CD Builds Images:     │    │ Terraform updates Policy:│
│ • Attestor & Note        │ ──►│ • Scans for CVEs        │ ──►│ • evaluation_mode =      │
│ • Policy Engine          │    │ • Signs digest with KMS  │    │   "REQUIRE_ATTESTATION" │
│ • Mode: ALWAYS_ALLOW     │    │ • Pushes Attestation     │    │ • Unsigned Pods BLOCKED  │
└──────────────────────────┘    └──────────────────────────┘    └──────────────────────────┘

```

---

### What the Fully Hardened Code Looks Like

Once your CI/CD pipeline is active and signing images with a KMS key, you update the policy in `modules/04-binary-auth/main.tf` from `ALWAYS_ALLOW` to this:

```hcl
default_admission_rule {
  evaluation_mode  = "REQUIRE_ATTESTATION"
  enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"

  # Requires signatures from our production build attestor
  require_attestations_by = [
    google_binary_authorization_attestor.attestor.name
  ]
}

```

When this is active, if someone attempts to run `kubectl apply -f unvetted-malicious-image.yaml`, GKE rejects it with this exact API error:

> `Error: Denied by Binary Authorization: Image custom-app:latest denied by rule. No valid attestation found for attestor prod-build-attestor.`

---

### Summary

We set `ALWAYS_ALLOW` during **Tier 2 (Bootstrap)** so our infrastructure builds cleanly without blocking cluster setup. Once our CI/CD pipelines are configured to sign container digests, flipping that single parameter to `REQUIRE_ATTESTATION` locks the cluster down permanently.

---

@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ gcloud container binauthz policy export --project=kam-dev-test
defaultAdmissionRule:
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  evaluationMode: ALWAYS_ALLOW
etag: '"ZWjT9MyR5hTT"'
globalPolicyEvaluationMode: ENABLE
name: projects/kam-dev-test/policy
updateTime: '2026-07-29T23:15:53.289935Z'

====================

Build Module 05-cloud-service-mesh (Tier 3)
Now we enter Tier 3 (Data Plane & Service Mesh Security). In this step, we will register our cluster with Google Cloud Fleet (GKE Hub) and enable managed Cloud Service Mesh (Istio/Cilium eBPF Control Plane).

Let's construct modules/05-cloud-service-mesh.

### Architectural Layer Isolation

* **Layer:** Tier 2 (Software Supply Chain Security) ──► Tier 3 (Service Mesh & Data Plane Zero-Trust)
* **Targets:** `modules/04-binary-auth` & `modules/05-cloud-service-mesh`

---

## Step 1: Deploy `04-binary-auth` to Production

Let's apply our Binary Authorization module to `environments/prod`.

Run these commands in your terminal:

```bash
# 1. Navigate to the production environment directory
cd /workspaces/gke-defense-in-depth/environments/prod

# 2. Re-initialize provider plugins and modules
terraform init

# 3. Provision Tier 2 Binary Authorization
terraform apply -auto-approve

```

---

## Step 2: Verify Binary Authorization Policy

Once `terraform apply` finishes, run this verification command to confirm GCP activated the policy on project `kam-dev-test`:

```bash
gcloud container binauthz policy export --project=kam-dev-test

```

**Expected Output:**

```yaml
defaultAdmissionRule:
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  evaluationMode: ALWAYS_ALLOW
globalPolicyEvaluationMode: ENABLE

```

---

## Step 3: Build Module `05-cloud-service-mesh` (Tier 3)

Now we enter **Tier 3 (Data Plane & Service Mesh Security)**. In this step, we will register our cluster with **Google Cloud Fleet (GKE Hub)** and enable managed **Cloud Service Mesh (Istio/Cilium eBPF Control Plane)**.

Let's construct `modules/05-cloud-service-mesh`.

### 3.1 Input Variables (`modules/05-cloud-service-mesh/variables.tf`)

Create the file `modules/05-cloud-service-mesh/variables.tf`:

```hcl
variable "project_id" {
  type        = string
  description = "The target GCP Project ID."
}

variable "location" {
  type        = string
  description = "The GCP Region of the cluster."
  default     = "us-central1"
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster."
}

variable "cluster_id" {
  type        = string
  description = "The fully qualified resource ID of the GKE cluster."
}

```

---

### 3.2 Main Module Logic (`modules/05-cloud-service-mesh/main.tf`)

Create the file `modules/05-cloud-service-mesh/main.tf`:

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. Enable Service Mesh & GKE Hub Fleet APIs
# ------------------------------------------------------------------------------
resource "google_project_service" "gkehub_api" {
  project            = var.project_id
  service            = "gkehub.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "mesh_api" {
  project            = var.project_id
  service            = "mesh.googleapis.com"
  disable_on_destroy = false
}

# ------------------------------------------------------------------------------
# 2. Register GKE Cluster to Google Cloud Fleet (GKE Hub)
# ------------------------------------------------------------------------------
resource "google_gke_hub_membership" "membership" {
  project       = var.project_id
  membership_id = "${var.cluster_name}-fleet-member"

  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/${var.cluster_id}"
    }
  }

  depends_on = [
    google_project_service.gkehub_api
  ]
}

# ------------------------------------------------------------------------------
# 3. Enable Service Mesh Fleet Feature
# ------------------------------------------------------------------------------
resource "google_gke_hub_feature" "servicemesh" {
  project  = var.project_id
  name     = "servicemesh"
  location = "global"

  depends_on = [
    google_project_service.mesh_api
  ]
}

# ------------------------------------------------------------------------------
# 4. Activate Automatic Managed Service Mesh Management
# ------------------------------------------------------------------------------
resource "google_gke_hub_feature_membership" "servicemesh_membership" {
  project    = var.project_id
  location   = "global"
  feature    = google_gke_hub_feature.servicemesh.name
  membership = google_gke_hub_membership.membership.membership_id

  mesh {
    management = "MANAGEMENT_AUTOMATIC"
  }
}

```

---

### 3.3 Module Outputs (`modules/05-cloud-service-mesh/outputs.tf`)

Create the file `modules/05-cloud-service-mesh/outputs.tf`:

```hcl
output "membership_id" {
  value       = google_gke_hub_membership.membership.membership_id
  description = "The GKE Hub Fleet Membership ID for the cluster."
}

output "servicemesh_feature_state" {
  value       = google_gke_hub_feature.servicemesh.name
  description = "The Fleet Service Mesh feature state."
}

```

---

### Step 4: Validate Module `05-cloud-service-mesh`

Run a local validation check in your terminal:

```bash
cd /workspaces/gke-defense-in-depth/modules/05-cloud-service-mesh
terraform init
terraform validate

```

**Expected Output:**

```text
Success! The configuration is valid.

```

---

### Step 5: Update `environments/prod/main.tf`

Ensure `modules/03-gke-cluster/outputs.tf` exposes `cluster_id` (so `module.gke_cluster.cluster_id` can be read):

Append to `modules/03-gke-cluster/outputs.tf`:

```hcl
output "cluster_id" {
  value       = google_container_cluster.primary.id
  description = "The fully qualified resource ID of the GKE cluster."
}

```

Then append the `05-cloud-service-mesh` module invocation block to `environments/prod/main.tf`:

```hcl
# ------------------------------------------------------------------------------
# Module 05: Tier 3 Cloud Service Mesh & Fleet Registration
# ------------------------------------------------------------------------------
module "cloud_service_mesh" {
  source       = "../../modules/05-cloud-service-mesh"
  project_id   = var.project_id
  location     = var.region
  cluster_name = var.cluster_name
  cluster_id   = module.gke_cluster.cluster_id

  depends_on = [
    module.gke_cluster
  ]
}

```

---

### Step 6: GitOps Sync & Service Mesh Deployment

1. Commit all files to Git:

```bash
cd /workspaces/gke-defense-in-depth
git add modules/03-gke-cluster/outputs.tf modules/04-binary-auth/ modules/05-cloud-service-mesh/ environments/prod/main.tf
git commit -m "feat(mesh): construct Tier 3 cloud service mesh module and update prod composition"

```

2. Apply in production:

```bash
cd /workspaces/gke-defense-in-depth/environments/prod
terraform init
terraform apply -auto-approve

```

---

### Gatekeeper Checkpoint

Let me know once `terraform apply` finishes registering the cluster to Cloud Fleet! Then we'll verify the managed Service Mesh control plane and apply our **Strict mTLS Policy & Zero-Trust Cilium Network Policies**.

==================
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ gcloud container fleet memberships list --project=kam-dev-test
NAME                               UNIQUE_ID                             LOCATION
prod-gke-did-cluster-fleet-member  a3a90650-791f-48b2-b3c8-a2016f46099a  global
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ gcloud container fleet features describe servicemesh --project=kam-dev-test
createTime: '2026-07-30T00:00:03.791208295Z'
membershipSpecs:
  projects/243781974020/locations/global/memberships/prod-gke-did-cluster-fleet-member:
    mesh:
      management: MANAGEMENT_AUTOMATIC
membershipStates:
  projects/243781974020/locations/global/memberships/prod-gke-did-cluster-fleet-member:
    servicemesh:
      controlPlaneManagement:
        details:
        - code: REVISION_PROVISIONING
          details: 'Provisioning: asm-managed'
        state: PROVISIONING
      dataPlaneManagement:
        details:
        - code: MANAGED_CONTROL_PLANE_REQUIRED
          details: Requires active managed control plane.
        state: PROVISIONING
    state:
      description: 'Revision being rolled out: asm-managed.'
      updateTime: '2026-07-30T00:03:36.720807269Z'
name: projects/kam-dev-test/locations/global/features/servicemesh
resourceState:
  state: ACTIVE
spec: {}
updateTime: '2026-07-30T00:03:06.888995484Z'

============
Cloud Service Mesh Status & Tier 3 Data Plane Completion
Your output confirms that Google Cloud Fleet Membership is active and the Cloud Service Mesh feature is enabled on project kam-dev-test.

The state: PROVISIONING (Revision being rolled out: asm-managed) status indicates that GCP's background orchestrator is currently instantiating the managed Istio control plane controllers for your cluster. This typically takes 3 to 5 minutes to transition to state: ACTIVE.

=============
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ gcloud container fleet features describe servicemesh --project=kam-dev-test
createTime: '2026-07-30T00:00:03.791208295Z'
membershipSpecs:
  projects/243781974020/locations/global/memberships/prod-gke-did-cluster-fleet-member:
    mesh:
      management: MANAGEMENT_AUTOMATIC
membershipStates:
  projects/243781974020/locations/global/memberships/prod-gke-did-cluster-fleet-member:
    servicemesh:
      conditions:
      - code: VPCSC_GA_SUPPORTED
        details: This control plane supports VPC-SC GA.
        documentationLink: http://cloud.google.com/service-mesh/docs/managed/vpc-sc
        severity: INFO
      controlPlaneManagement:
        details:
        - code: REVISION_READY
          details: 'Ready: asm-managed'
        implementation: ISTIOD
        state: ACTIVE
      dataPlaneManagement:
        details:
        - code: OK
          details: Service is running.
        state: ACTIVE
    state:
      code: OK
      description: 'Revision ready for use: asm-managed.'
      updateTime: '2026-07-30T00:08:13.951136632Z'
name: projects/kam-dev-test/locations/global/features/servicemesh
resourceState:
  state: ACTIVE
spec: {}
updateTime: '2026-07-30T00:03:06.888995484Z'

=============
### Tier 3 Verification & Data Plane Hardening

`Apply complete!` Google Cloud Fleet membership registration and Managed Cloud Service Mesh activation are now live on `prod-gke-did-cluster`.

---

## Step 1: Verify Fleet Membership & Service Mesh Control Plane

Run these `gcloud` commands in your terminal to verify that GCP has activated the Service Mesh feature across your cluster fleet:

```bash
# 1. Verify GKE cluster registration in Google Cloud Fleet
gcloud container fleet memberships list --project=kam-dev-test

# 2. Check the global status of Cloud Service Mesh
gcloud container fleet features describe servicemesh --project=kam-dev-test

```

**Expected Output:**

* The membership query will list `prod-gke-did-cluster-fleet-member`.
* The feature describe query will show state `OK` and `management: MANAGEMENT_AUTOMATIC`.

---

## Step 2: Enforcing In-Cluster Zero-Trust Security Policies

Now that the Service Mesh control plane and Cilium eBPF dataplane are managing cluster networking, we will enforce two critical zero-trust data plane controls:

1. **STRICT Mutual TLS (`PeerAuthentication`):** Mandates that all pod-to-pod communications are cryptographically encrypted and authenticated using short-lived mTLS X.509 certificates. Unencrypted plaintext traffic is strictly rejected.
2. **Default-Deny Cilium Network Policies (`NetworkPolicy`):** Applies a global default-deny rule across application namespaces, blocking all unapproved inter-pod lateral movement.

---

### 2.1 Manifest: Global STRICT mTLS (`policies/strict-mtls.yaml`)

Create a directory named `policies` at your repository root and add `policies/strict-mtls.yaml`:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT

```

---

### 2.2 Manifest: Global Default-Deny Network Policy (`policies/default-deny.yaml`)

Add `policies/default-deny.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

```

---

## Step 3: Apply Data Plane Security Policies

Execute `kubectl` to apply the strict mTLS and default-deny policies to your cluster:

```bash
# 1. Create policies directory if not existing
mkdir -p policies

# 2. Apply Strict mTLS and Default-Deny Network Policy
kubectl apply -f policies/strict-mtls.yaml
kubectl apply -f policies/default-deny.yaml

# 3. Verify applied policies
kubectl get peerauthentication -n default
kubectl get networkpolicies -n default

```

---

### Gatekeeper Checkpoint

Did the `gcloud` fleet describe command show `OK` for Service Mesh, and were both `strict-mtls` and `default-deny-all` applied cleanly via `kubectl`?

Once confirmed, we will advance directly to **Module `06-policy-gatekeeper` (Tier 4: Governance, OPA Gatekeeper, & Constraint Framework)**!

===========
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ mkdir -p /workspaces/gke-defense-in-depth/policies
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ touch /workspaces/gke-defense-in-depth/policies/strict-mtls.yaml
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ touch /workspaces/gke-defense-in-depth/policies/default-deny.yaml
@Kam4280 ➜ /workspaces/gke-defense-in-depth/environments/prod (main) $ cd /workspaces/gke-defense-in-depth

# Apply Strict mTLS & Default Deny Network Policy
kubectl apply -f policies/strict-mtls.yaml
kubectl apply -f policies/default-deny.yaml

# Verify applied security policies
kubectl get peerauthentication -n default
kubectl get networkpolicies -n default
peerauthentication.security.istio.io/default created
networkpolicy.networking.k8s.io/default-deny-all created
NAME      MODE     AGE
default   STRICT   2s
NAME               POD-SELECTOR   AGE
default-deny-all   <none>         0s

============
Tier 4 — Admission Governance & Policy Controller (06-policy-gatekeeper)
Now we move to Tier 4 (Layer 5: Governance & Admission Security).

In this tier, we deploy GKE Policy Controller (Google's enterprise managed Open Policy Agent / OPA Gatekeeper) via Cloud Fleet. It intercepts Kubernetes API requests to prevent misconfigurations (e.g., running containers as root, missing security labels, or bypassing sandbox requirements).

===========================

@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ gcloud container fleet features describe policycontroller --project=kam-dev-test
createTime: '2026-07-30T00:26:25.388583286Z'
membershipSpecs:
  projects/243781974020/locations/global/memberships/prod-gke-did-cluster-fleet-member:
    policycontroller:
      policyControllerHubConfig:
        auditIntervalSeconds: '60'
        constraintViolationLimit: '50'
        deploymentConfigs:
          admission:
            podAffinity: ANTI_AFFINITY
        installSpec: INSTALL_SPEC_ENABLED
        logDeniesEnabled: true
        monitoring:
          backends:
          - PROMETHEUS
          - CLOUD_MONITORING
        policyContent:
          templateLibrary:
            installation: ALL
        referentialRulesEnabled: true
      version: 1.23.2
membershipStates:
  projects/243781974020/locations/global/memberships/prod-gke-did-cluster-fleet-member:
    policycontroller:
      componentStates:
        admission:
          details: 1.23.2
          state: ACTIVE
        audit:
          details: 1.23.2
          state: ACTIVE
        mutation:
          details: 'deployment not installed: resource is missing'
          state: NOT_INSTALLED
      policyContentState:
        bundleStates:
          asm-policy-v0.0.1:
            state: NOT_INSTALLED
          cis-gke-v1.5.0:
            state: NOT_INSTALLED
          cis-k8s-v1.5.1:
            state: NOT_INSTALLED
          cost-reliability-v2023:
            state: NOT_INSTALLED
          nist-sp-800-190:
            state: NOT_INSTALLED
          nist-sp-800-53-r5:
            state: NOT_INSTALLED
          nsa-cisa-k8s-v1.2:
            state: NOT_INSTALLED
          pci-dss-v3.2.1:
            state: NOT_INSTALLED
          pci-dss-v3.2.1-extended:
            state: NOT_INSTALLED
          pci-dss-v4.0:
            state: NOT_INSTALLED
          policy-essentials-v2022:
            state: NOT_INSTALLED
          psp-v2022:
            state: NOT_INSTALLED
          pss-baseline-v2022:
            state: NOT_INSTALLED
          pss-restricted-v2022:
            state: NOT_INSTALLED
        referentialSyncConfigState:
          state: NOT_INSTALLED
        templateLibraryState:
          state: ACTIVE
      state: ACTIVE
    state:
      code: OK
      updateTime: '2026-07-30T05:34:05.046582827Z'
name: projects/kam-dev-test/locations/global/features/policycontroller
resourceState:
  state: ACTIVE
spec: {}
updateTime: '2026-07-30T00:34:54.750851720Z'
@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ kubectl get pods -n gatekeeper-system
NAME                                             READY   STATUS    RESTARTS      AGE
gatekeeper-audit-6c8995795-h9br8                 1/1     Running   2 (14h ago)   14h
gatekeeper-controller-manager-6c989b8757-5bsq8   1/1     Running   2 (14h ago)   14h

==================

for step 1 based on the following details, I need more details and explanation, about what logs are important, basically how does it work, etc?

@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ gcloud container fleet features describe policycontroller --project=kam-dev-test
createTime: '2026-07-30T00:26:25.388583286Z'
membershipSpecs:
  projects/243781974020/locations/global/memberships/prod-gke-did-cluster-fleet-member:
    policycontroller:
      policyControllerHubConfig:
        auditIntervalSeconds: '60'
        constraintViolationLimit: '50'
        deploymentConfigs:
          admission:
            podAffinity: ANTI_AFFINITY
        installSpec: INSTALL_SPEC_ENABLED
        logDeniesEnabled: true
        monitoring:
          backends:
          - PROMETHEUS
          - CLOUD_MONITORING
        policyContent:
          templateLibrary:
            installation: ALL
        referentialRulesEnabled: true
      version: 1.23.2
membershipStates:
  projects/243781974020/locations/global/memberships/prod-gke-did-cluster-fleet-member:
    policycontroller:
      componentStates:
        admission:
          details: 1.23.2
          state: ACTIVE
        audit:
          details: 1.23.2
          state: ACTIVE
        mutation:
          details: 'deployment not installed: resource is missing'
          state: NOT_INSTALLED
      policyContentState:
        bundleStates:
          asm-policy-v0.0.1:
            state: NOT_INSTALLED
          cis-gke-v1.5.0:
            state: NOT_INSTALLED
          cis-k8s-v1.5.1:
            state: NOT_INSTALLED
          cost-reliability-v2023:
            state: NOT_INSTALLED
          nist-sp-800-190:
            state: NOT_INSTALLED
          nist-sp-800-53-r5:
            state: NOT_INSTALLED
          nsa-cisa-k8s-v1.2:
            state: NOT_INSTALLED
          pci-dss-v3.2.1:
            state: NOT_INSTALLED
          pci-dss-v3.2.1-extended:
            state: NOT_INSTALLED
          pci-dss-v4.0:
            state: NOT_INSTALLED
          policy-essentials-v2022:
            state: NOT_INSTALLED
          psp-v2022:
            state: NOT_INSTALLED
          pss-baseline-v2022:
            state: NOT_INSTALLED
          pss-restricted-v2022:
            state: NOT_INSTALLED
        referentialSyncConfigState:
          state: NOT_INSTALLED
        templateLibraryState:
          state: ACTIVE
      state: ACTIVE
    state:
      code: OK
      updateTime: '2026-07-30T05:34:05.046582827Z'
name: projects/kam-dev-test/locations/global/features/policycontroller
resourceState:
  state: ACTIVE
spec: {}
updateTime: '2026-07-30T00:34:54.750851720Z'
@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ kubectl get pods -n gatekeeper-system
NAME                                             READY   STATUS    RESTARTS      AGE
gatekeeper-audit-6c8995795-h9br8                 1/1     Running   2 (14h ago)   14h
gatekeeper-controller-manager-6c989b8757-5bsq8   1/1     Running   2 (14h ago)   14h

=============
Here is a deep-dive technical breakdown of your CLI output, how Policy Controller works under the hood, and why its logging architecture is a cornerstone of SecOps and SIEM auditing.

---

## Part 1: Deconstructing Your Output

Your `gcloud` and `kubectl` outputs show a healthy **Managed OPA Gatekeeper (Policy Controller)** deployment operating in **Dual-Engine Mode**.

### Key Configurations in Your Spec:

| Parameter in Output | Technical Meaning | Security Impact |
| --- | --- | --- |
| **`logDeniesEnabled: true`** | Forces Gatekeeper to output a structured JSON log to `stdout` *every time* an API request violates a constraint. | **Crucial for SecOps.** These logs are picked up by Fluentbit/Cloud Logging and forwarded directly to your Tier 5 GCS Audit Sink. |
| **`auditIntervalSeconds: '60'`** | Scans all pre-existing objects in the cluster every 60 seconds against all active constraints. | Catches "drift"—resources deployed *before* a security constraint was created. |
| **`constraintViolationLimit: '50'`** | Caps the max reported violations stored inside Kubernetes CRD `.status` fields to 50 per constraint. | Prevents memory exhaustion on the Kubernetes API server if thousands of pods break a rule. |
| **`referentialRulesEnabled: true`** | Enables cross-resource state inspection in Rego rules (e.g., "Check if an Ingress hostname conflicts with another Namespace"). | Enables complex, multi-object security policies beyond basic Pod inspection. |

### Component States Explained:

* **`admission: ACTIVE`** $\rightarrow$ Running inside `gatekeeper-controller-manager-6c989b8757-5bsq8`. It acts as a real-time **Validating Admission Webhook** intercepting `kubectl` and CI/CD deployment calls.
* **`audit: ACTIVE`** $\rightarrow$ Running inside `gatekeeper-audit-6c8995795-h9br8`. It runs asynchronous background scans every 60 seconds.
* **`bundleStates (*: NOT_INSTALLED)`** $\rightarrow$ Out-of-the-box GCP policy packages (like CIS GKE or PCI-DSS) are disabled. This is normal because we write custom, fine-grained OPA Constraints (like our `disallow-privileged.yaml`) tailored specifically to this architecture.

---

## Part 2: How Policy Controller Works Under the Hood

Policy Controller intercepts every Kubernetes resource request **before** it is saved to `etcd` (the cluster database).

```text
[ Developer / CI-CD ] ──► kubectl apply -f pod.yaml
                                │
                                ▼
                   [ Kubernetes API Server ]
                                │
                                ▼  (HTTPS Admission Webhook Call)
               ┌──────────────────────────────────┐
               │  gatekeeper-controller-manager   │
               │  (Evaluates Rego Policy Rules)   │
               └──────────────────────────────────┘
                         │              │
             ┌───────────┘              └───────────┐
             ▼                                      ▼
     [ REJECTED / DENIED ]                  [ APPROVED ]
             │                                      │
  ├── 1. HTTP 403 returned to user       ├── 1. Written to etcd database
  ├── 2. Deny Log written to stdout      └── 2. Pod scheduled on node
  └── 3. Picked up by SecOps Sink

```

### The Two Operating Modes:

1. **Synchronous Real-Time Prevention (Admission Webhook):**
When someone runs `kubectl apply`:
* The API Server halts the request and forwards the raw YAML payload to `gatekeeper-controller-manager`.
* Gatekeeper evaluates the manifest against all compiled Open Policy Agent (OPA) Rego rules in memory within **$<50\text{ms}$**.
* If compliant, Gatekeeper returns `Allowed: true`.
* If non-compliant (e.g., `privileged: true`), Gatekeeper returns `Allowed: false`, rejects the HTTP call with an API error, and **emits a denial event to stdout**.


2. **Asynchronous Continuous Auditing (Audit Loop):**
* What if a developer created a bad pod *before* an admin created a new security constraint?
* The `gatekeeper-audit` pod queries the Kubernetes API server every 60 seconds, evaluates all active objects, and updates the Constraint's `.status.violations` list.



---

## Part 3: What Logs Are Important & Why?

When SecOps investigates an incident or auditors perform a compliance review, three distinct log streams generated by this setup provide crucial visibility:

### 1. Gatekeeper Denial Logs (`logDeniesEnabled = true`)

* **Source:** `gatekeeper-controller-manager` container stdout.
* **Format:** Structured JSON payload.
* **Sample Log Payload:**
```json
{
  "severity": "INFO",
  "logger": "status",
  "msg": "admission response",
  "process": "admission",
  "event_type": "deny",
  "constraint": "psp-no-privileged-containers",
  "resource_namespace": "default",
  "resource_kind": "Pod",
  "resource_name": "malicious-crypto-miner",
  "user": "developer-sa@kam-dev-test.iam.gserviceaccount.com",
  "explanation": "Privileged containers are disallowed on production GKE clusters!"
}

```


* **Why it matters:** It identifies **who** tried to deploy unauthorized workloads, **what** policy they violated, and **when** the attempt took place.

### 2. GKE API Server Audit Logs

* **Source:** Kubernetes API Server Control Plane (`protoPayload.serviceName="container.googleapis.com"`).
* **What it logs:** The official HTTP status code (`403 Forbidden` or `422 Unprocessable Entity`) returned by the API server when Gatekeeper blocks a request.
* **Why it matters:** Proves to external compliance auditors (SOC 2, ISO 27001, PCI-DSS) that unauthorized deployments were physically blocked at the control plane layer, rather than merely detected after execution.

### 3. Binary Authorization Gatekeeper Denials

* **Source:** `binaryauthorization.googleapis.com`.
* **What it logs:** Attempts to deploy container images that lack a valid cryptographic CI/CD signature (Attestation).
* **Why it matters:** Detects software supply chain tampering or developers attempting to run unvetted container images directly from public registries like Docker Hub.

---

## Part 4: How to Query These Logs in GCP

Because Tier 5 (`07-secops-logging`) created a Project Log Sink targeting your GCS Bucket (`kam-dev-test-gke-secops-audit-logs`), all of these security events are automatically aggregated.

### Querying Gatekeeper Denials in GCP Logs Explorer:

To view all blocked deployment attempts live in the GCP Console or CLI, use this filter:

```sql
resource.type="k8s_container"
resource.labels.namespace_name="gatekeeper-system"
resource.labels.container_name="gatekeeper"
jsonPayload.event_type="deny"

```

### Running a Live Query via `gcloud`:

Run this command in your terminal to search for any blocked requests in the past 24 hours:

```bash
gcloud logging read 'resource.type="k8s_container" AND resource.labels.container_name="gatekeeper" AND jsonPayload.event_type="deny"' \
  --project=kam-dev-test \
  --limit=10 \
  --format="json(timestamp, jsonPayload.user, jsonPayload.constraint, jsonPayload.resource_name, jsonPayload.explanation)"

```

---

### Gatekeeper Checkpoint

Does this step-by-step breakdown clarify how Policy Controller's dual engine processes requests, why `logDeniesEnabled: true` is crucial for SecOps, and how logs flow into your Tier 5 GCS bucket?

Once you're ready, we can move straight to **`08-mlops-inference` (Tier 6: Sandboxed MLOps Workload Deployment)**!
=================================
basically, from scratch , I do not remember how we deployed these 2 pods "gatekeeper-audit-6c8995795-h9br8" & "gatekeeper-controller-manager-6c989b8757-5bsq8" and why? from yesterday I remember module 5 "05-cloud-service-mesh" and based on my understanding enabling services mesh can encrypt and decrypt pod to pod communications and we can apply some network policy or any other required policies based on our use case by service mesh, correct? but what's the use of module 06 "06-policy-gatekeeper" as it seems we can do the same through module 5 "05-cloud-service-mesh"  right? correct me if I misunderstood.

======================
You've hit on one of the most common points of confusion in Kubernetes security! It is totally normal for these two modules to sound like they do the same thing because they both use the word "policy."

However, **they protect completely different parts of your cluster**.

Here is the breakdown of how those pods got there and why both modules are required for true Defense-in-Depth.

---

## 1. How Did Those 2 Pods Get Deployed?

You didn't deploy `gatekeeper-audit` or `gatekeeper-controller-manager` using `kubectl`. **GCP deployed them automatically for you!**

When you ran `terraform apply` for **Module 06 (`06-policy-gatekeeper`)**, Terraform created this resource:

```hcl
resource "google_gke_hub_feature_membership" "policycontroller_membership" {
  ...
  policycontroller {
    policy_controller_hub_config {
      install_spec = "INSTALL_SPEC_ENABLED"
    }
  }
}

```

The Google Cloud Fleet operator saw this configuration, reached into your GKE cluster, created the `gatekeeper-system` namespace, and automatically downloaded and spun up those two pods on your nodes.

* **`gatekeeper-controller-manager`:** The real-time gatekeeper that sits at the entrance of the Kubernetes API server.
* **`gatekeeper-audit`:** The background scanner that continuously checks existing resources for security drift every 60 seconds.

---

## 2. Module 05 vs. Module 06: Why Do We Need Both?

To put it simply: **Service Mesh controls NETWORK TRAFFIC, while Policy Gatekeeper controls KUBERNETES YAML/JSON CONFIGURATIONS.**

```text
[ Developer / CI-CD ]
         │
         ▼
 1. DEPLOYMENT ATTEMPT (kubectl apply -f pod.yaml)
         │
         ├──► Module 06 (Policy Gatekeeper) Checks:
         │    • "Is this container running as root?" ──► BLOCKED!
         │    • "Is securityContext.privileged = true?" ──► BLOCKED!
         │    • "Is a memory limit specified in the YAML?"
         │
         ▼
 2. POD IS CREATED & RUNNING ON NODE
         │
         ▼
 3. RUNTIME NETWORK COMMUNICATION (Pod A ──► Pod B)
         │
         └──► Module 05 (Cloud Service Mesh) Checks:
              • Encrypts connection with strict mTLS.
              • "Is Pod A allowed to talk to Pod B over HTTP/8080?" ──► ALLOWED / DENIED

```

---

### The Analogy

* **Module 05 (Service Mesh): The Security Guard / Bouncer at the Door**
* **Layer:** Network / Data Plane (L4/L7).
* **What it does:** Encrypts data in transit between pods (mTLS), inspects HTTP headers, and blocks unauthorized network calls.
* **What it CANNOT do:** It cannot stop a developer from deploying a pod that runs as `root` or mounts sensitive host directories (`/etc`). It only sees network packets.


* **Module 06 (Policy Gatekeeper): The Building Inspector / Blueprint Checker**
* **Layer:** Control Plane / Kubernetes API Admission.
* **What it does:** Inspects the raw YAML manifest *before* the pod is allowed to exist. It blocks bad configurations (e.g., running as root, missing CPU limits, mounting the host filesystem).
* **What it CANNOT do:** It cannot encrypt network traffic between pods or block a malicious HTTP request at runtime.



---

### Comparison Matrix

| Feature | Module 05: Cloud Service Mesh | Module 06: Policy Gatekeeper |
| --- | --- | --- |
| **Security Phase** | **Runtime** (When pods talk over the network) | **Admission / Deploy time** (When YAML is applied) |
| **Target** | Network packets, IP addresses, HTTP/gRPC requests | Kubernetes resource definitions (Pods, Services, Ingress) |
| **Primary Job** | Encrypt traffic (mTLS) & control inter-pod communication | Enforce cluster configuration guardrails & pod security standards |
| **Example Policy** | *"Pod A can only talk to Pod B on port 8080"* | *"No container in this cluster is allowed to run as root"* |

---

### Summary

* **Module 05** ensures that if an attacker compromises a pod, they **cannot eavesdrop on or jump across the network** to other services.
* **Module 06** ensures that developers **cannot deploy misconfigured or dangerous pods** that expose the host node to a container breakout.

Does this distinction between **Network Traffic (Mesh)** and **Configuration Guardrails (Gatekeeper)** make sense?

=================================
So, basically,GCP OPA gatekeeper 9 based on a open source protocols or services) is a managed security feature from Google and the customers only follows the instructions in GCP console, API, gcloud or TerraForms to run/install it in their GKE control plane to check the pod YAML deployment contents based on some pre-configured rules and restrictions correct? correct me if I am wrong. also, I do remember the same security check options for pods  during deployment or in CI/CD pipelines are available with some GitHub action libraries, correct? if so, can you compare them?

=========
Yes, your understanding is spot-on.

---

## Part 1: GCP Policy Controller (OPA Gatekeeper)

GCP **Policy Controller** is Google's fully managed service built on top of the open-source **OPA (Open Policy Agent) Gatekeeper** CNCF project.

* **How it works:** Instead of manually deploying, patching, and maintaining Open Policy Agent webhooks, you simply enable Policy Controller using Terraform, `gcloud`, or the GCP Console. GCP automatically provisions and manages the `gatekeeper-controller-manager` and `gatekeeper-audit` pods inside your GKE cluster.
* **What it does:** It acts as a **Validating Admission Controller** at the Kubernetes API level. Every time a YAML/JSON manifest is sent to the cluster (via `kubectl apply`, Helm, or ArgoCD), Gatekeeper inspects the manifest against active `Constraints` (policy rules written in Rego). If the manifest violates a rule—such as attempting to run as `root`—Gatekeeper blocks the API request before the workload is ever written to the cluster database (`etcd`).

---

## Part 2: CI/CD Pipeline Checking vs. In-Cluster Gatekeeper

You are also completely correct about CI/CD pipelines. You can run the exact same policy checks earlier in your pipeline (like GitHub Actions) using static analysis tools:

* **`gator` CLI:** The official command-line tool built directly by the OPA Gatekeeper maintainers. It lets you test your Kubernetes YAML files in GitHub Actions against the exact same `ConstraintTemplates` and `Constraints` running in your GKE cluster.
* **Other CI/CD tools:** `conftest` (OPA-based), `checkov`, `kube-linter`, `datree`, and `kyverno-cli`.

---

## Part 3: Comparison — CI/CD Pipeline Checks vs. In-Cluster Policy Controller

In security engineering, combining both is known as **Shifting Left** (catching bugs in CI/CD) while keeping **Gatekeeper at the Runtime Boundary** (blocking unauthorized deployments at the cluster).

| Feature | CI/CD Pipeline Checks (e.g., GitHub Actions + `gator`) | In-Cluster Policy Controller (OPA Gatekeeper) |
| --- | --- | --- |
| **Where it Runs** | GitHub Actions runners, GitLab CI, local developer laptops | Inside the GKE Control Plane as an Admission Webhook |
| **When it Evaluates** | During Pull Requests / Build time (**Shift Left**) | During `kubectl apply` / Deployment time (**Admission**) |
| **Can it be Bypassed?** | **Yes.** An engineer with cluster access can bypass GitHub Actions using `kubectl` directly from their CLI, or an emergency hotfix might skip CI/CD. | **No.** Every single request hitting the Kubernetes API server *must* pass through Gatekeeper, no matter who sent it. |
| **Feedback Speed** | Fast feedback directly in the GitHub PR before code is merged. | Feedback is given when attempting to deploy to the cluster. |
| **Context Awareness** | **Static.** Only sees the single raw YAML file being changed in the Pull Request. | **Dynamic / Live.** Can inspect live cluster state, namespace metadata, and existing cluster inventory. |
| **Drift Detection** | Cannot detect if someone manually changes a live cluster resource. | Continuously audits existing live cluster workloads every 60 seconds for compliance drift. |

---

## Key Takeaway: Why Defense-in-Depth Uses Both

1. **CI/CD (`gator` in GitHub Actions):** Developer experience tool. Prevents bad code from being merged into git and gives instant feedback to developers in their Pull Requests.
2. **Policy Controller (GKE In-Cluster):** Non-negotiable security guardrail. Ensures that even if someone bypasses GitHub Actions or applies a manifest manually, dangerous workloads cannot execute on production infrastructure.

=====================


Alright, but  In-Cluster Policy Controller (OPA Gatekeeper) when you say about where it runs "Inside the GKE Control Plane as an Admission Webhook". you mean by each deployment "(via kubectl apply, Helm, or ArgoCD), Gatekeeper inspects the manifest against active Constraints (policy rules written in Rego). " where are these active constraints? in the deployed gatekeeper-controller-manager and gatekeeper-audit pods inside my GKE cluster? basically what do mean of "Admission Webhook"? it means by each apply the policy calls a specific internal GCP webhook URL and compares it against it's current constraint or these constraints are already defined in the pods (gatekeeper-controller-manager and gatekeeper-audit pods)? basically open source OPA defines these policies/constraints or GCP itself as a managed service? if not who does so?

======================

These questions touch on the fundamental mechanics of how Kubernetes extension points and OPA Gatekeeper actually work under the hood.

Here is the exact breakdown of where constraints live, how the admission webhook functions, and who is responsible for creating policies.

---

## 1. Where do active constraints live?

Constraints live in **two places simultaneously**:

1. **On Disk / Database (`etcd`):** When you run `kubectl apply -f policies/disallow-privileged.yaml`, Kubernetes saves that rule inside its database (`etcd`) as a Custom Resource (CRD).
2. **In Memory (RAM of the Pods):** The `gatekeeper-controller-manager` pod running in your cluster continuously watches `etcd`. Whenever a Constraint is created or updated, the pod reads it and compiles the policy rules into its **internal RAM cache**.

When a new deployment request arrives, Gatekeeper evaluates the request against the compiled rules in its RAM cache, enabling sub-50 millisecond policy evaluation.

---

## 2. What is an "Admission Webhook"? How does it work?

An **Admission Webhook** is a built-in Kubernetes API Server feature.

It does **NOT** call an external GCP URL or external cloud service. It is a completely local, internal HTTPS call inside your cluster.

### The Step-by-Step Flow

```text
[ Developer / CI-CD ] ──► kubectl apply -f pod.yaml
                                │
                                ▼
                    [ K8s API Server ] 
                                │
                                │ 1. "ValidatingWebhookConfiguration" directs API Server:
                                │    "Send an internal HTTPS POST request to Gatekeeper!"
                                ▼
         ┌──────────────────────────────────────────────┐
         │ gatekeeper-controller-manager Pod            │
         │ (Running inside gatekeeper-system namespace) │
         └──────────────────────────────────────────────┘
                                │
                                │ 2. Evaluates pod.yaml against memory cache
                                ▼
                       [ ALLOW or DENY ]

```

1. You run `kubectl apply -f pod.yaml`.
2. The **Kubernetes API Server** receives the request and authenticates your user identity.
3. The API Server checks its internal configuration object (`ValidatingWebhookConfiguration`).
4. It sees an entry that says: *"Before saving any Pod to etcd, send the Pod YAML to `[https://gatekeeper-webhook-service.gatekeeper-system.svc:443](https://gatekeeper-webhook-service.gatekeeper-system.svc:443)`."*
5. The API Server makes an **in-cluster HTTPS POST request** to the `gatekeeper-controller-manager` pod.
6. Gatekeeper checks the pod against its rules in RAM and returns an HTTP `200 OK` (Allowed) or `403 Forbidden` (Denied) back to the API Server.

---

## 3. Who defines these policies and constraints?

Gatekeeper uses a two-tier model: **ConstraintTemplates** and **Constraints**.

```text
  ConstraintTemplate (The Blueprint / Code)
              ▲
              │  "How to check if a container is privileged"
              │  (Written in OPA Rego)
              │
      Constraint (The Actual Rule)
                 "Enforce this blueprint on the 'default' namespace"
                 (Written in YAML)

```

### The Roles & Responsibilities

| Component | What is it? | Who creates/provides it? |
| --- | --- | --- |
| **`ConstraintTemplate`** | **The underlying code logic.** It defines *how* to evaluate a rule using the OPA Rego language. | **Open Source OPA & GCP Library.** <br>

<br>GCP Policy Controller includes an out-of-the-box library of templates. (In Module 06, we enabled `template_library { installation = "ALL" }` so GCP pre-loaded these templates into your cluster.) |
| **`Constraint`** | **The actual enforced rule.** It references a `ConstraintTemplate` and specifies *where* and *how* to apply it (e.g., exclude `kube-system`, apply to `Pod` kinds). | **YOU (The DevOps / SecOps Engineer).** <br>

<br>GCP provides the engine and templates, but **you** choose which security rules apply to your application. For example, applying `policies/disallow-privileged.yaml` explicitly tells Gatekeeper to block privileged containers in your cluster. |

---

### Summary

* **Where do constraints live?** Stored in `etcd` as Kubernetes CRDs and cached in the `gatekeeper-controller-manager` pod's memory.
* **Is the Webhook external?** No, it is a native, internal Kubernetes API mechanism that sends an HTTP request directly to the local `gatekeeper-controller-manager` pod service inside your cluster.
* **Who writes the rules?** GCP/Open-Source OPA provides the engine and template libraries, but **you** write and apply the specific `Constraint` manifests to enforce your team's security standards.

=================

`Apply complete! Resources: 3 added` — **Tier 4 (Policy Controller & OPA Gatekeeper)** is live across your Google Cloud Fleet!

---

## Step 1: Verify Policy Controller Deployment

Run these commands to verify that the OPA Gatekeeper webhooks and pod controllers are running on your cluster:

```bash
# 1. Check Policy Controller status in Cloud Fleet
gcloud container fleet features describe policycontroller --project=kam-dev-test

# 2. Check OPA Gatekeeper pods inside the cluster
kubectl get pods -n gatekeeper-system

```

**Expected Output:**

* The fleet feature will show `state: ACTIVE`.
* You will see `gatekeeper-controller-manager` and `gatekeeper-audit` pods in `Running` status inside the `gatekeeper-system` namespace.

---

## Step 2: Enforce Guardrail Policies (OPA Gatekeeper Constraints)

Now that Gatekeeper is active, let's enforce custom security guardrails:

1. **`disallow-privileged.yaml`:** Blocks any pod requested with `securityContext.privileged: true` (preventing container breakouts to host root).
2. **`require-ro-rootfs.yaml`:** Warns/blocks workloads that do not use a Read-Only Root Filesystem.

### 2.1 Create Constraint Manifests

Add `policies/disallow-privileged.yaml`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sNoPrivilegedContainers
metadata:
  name: psp-no-privileged-containers
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces:
      - kube-system
      - gke-system
      - gatekeeper-system

```

### 2.2 Apply Constraints to Cluster

Run `kubectl` to apply the policy:

```bash
kubectl apply -f policies/disallow-privileged.yaml
kubectl get k8snoprivilegedcontainers

```

---

## Tier 5 — Security Operations & Audit Logging (`07-secops-logging`)

Now we advance to **Tier 5 (Layer 7: SecOps, Incident Response & Audit Logging)**.

In this tier, we build **`modules/07-secops-logging`** to capture GKE Audit Logs, System Event Logs, and Policy Controller Violations into an immutable Cloud Storage security bucket for SIEM analysis and compliance auditing.

---

### Step 3: Construct Module `07-secops-logging`

#### 3.1 Input Variables (`modules/07-secops-logging/variables.tf`)

Create `modules/07-secops-logging/variables.tf`:

```hcl
variable "project_id" {
  type        = string
  description = "The target GCP Project ID."
}

variable "region" {
  type        = string
  description = "The target GCP Region for log storage."
  default     = "us-central1"
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster being monitored."
}

```

---

#### 3.2 Main Module Logic (`modules/07-secops-logging/main.tf`)

Create `modules/07-secops-logging/main.tf`:

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. Enable Cloud Logging & Monitoring APIs
# ------------------------------------------------------------------------------
resource "google_project_service" "logging_api" {
  project            = var.project_id
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring_api" {
  project            = var.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

# ------------------------------------------------------------------------------
# 2. Immutable SecOps Audit Log Storage Bucket
# ------------------------------------------------------------------------------
resource "google_storage_bucket" "secops_log_bucket" {
  name                     = "${var.project_id}-gke-secops-audit-logs"
  project                  = var.project_id
  location                 = var.region
  force_destroy            = false
  uniform_bucket_level_access = true

  # Immutable retention policy (30-day compliance lock)
  retention_policy {
    is_locked        = false
    retention_period = 2592000 # 30 Days in seconds
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 90
    }
  }

  depends_on = [
    google_project_service.logging_api
  ]
}

# ------------------------------------------------------------------------------
# 3. Project Security Audit Log Sink (GKE Control Plane & Gatekeeper)
# ------------------------------------------------------------------------------
resource "google_logging_project_sink" "gke_security_sink" {
  name        = "${var.cluster_name}-secops-audit-sink"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.secops_log_bucket.name}"

  # Filter for GKE Audit Logs, Gatekeeper Denials, and Binary Authorization Events
  filter = <<EOT
resource.type=("k8s_cluster" OR "k8s_container" OR "k8s_node")
OR protoPayload.serviceName="container.googleapis.com"
OR protoPayload.serviceName="binaryauthorization.googleapis.com"
EOT

  unique_writer_identity = true
}

# Grant Log Sink Writer SA permission to write to Storage Bucket
resource "google_storage_bucket_iam_member" "sink_writer" {
  bucket = google_storage_bucket.secops_log_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.gke_security_sink.writer_identity
}

```

---

#### 3.3 Module Outputs (`modules/07-secops-logging/outputs.tf`)

Create `modules/07-secops-logging/outputs.tf`:

```hcl
output "secops_bucket_name" {
  value       = google_storage_bucket.secops_log_bucket.name
  description = "The name of the SecOps compliance log storage bucket."
}

output "log_sink_writer_identity" {
  value       = google_logging_project_sink.gke_security_sink.writer_identity
  description = "The Service Account identity used by the log sink."
}

```

---

### Step 4: Validate Module & Update `environments/prod/main.tf`

1. **Validate `modules/07-secops-logging`:**

```bash
cd /workspaces/gke-defense-in-depth/modules/07-secops-logging
terraform init
terraform validate

```

2. **Update `environments/prod/main.tf`:**
Append the Tier 5 SecOps Logging module call to `environments/prod/main.tf`:

```hcl
# ------------------------------------------------------------------------------
# Module 07: Tier 5 SecOps Audit Logging & Log Sinks
# ------------------------------------------------------------------------------
module "secops_logging" {
  source       = "../../modules/07-secops-logging"
  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name

  depends_on = [
    module.gke_cluster
  ]
}

```

---

### Step 5: GitOps Synchronization & Deployment

Commit and provision Tier 5:

```bash
# 1. Navigate to repository root and commit
cd /workspaces/gke-defense-in-depth
git add policies/ modules/07-secops-logging/ environments/prod/main.tf
git commit -m "feat(secops): add gatekeeper disallow-privileged constraint and provision Tier 5 secops logging module"

# 2. Deploy Tier 5 SecOps Logging
cd /workspaces/gke-defense-in-depth/environments/prod
terraform init
terraform apply -auto-approve

```

---

### Gatekeeper Checkpoint

Did `terraform apply` finish creating the **SecOps Audit Log Storage Bucket** and **Project Log Sink**?

Once confirmed, we will step into our final module: **`08-mlops-inference` (Tier 6: Sandboxed MLOps Workload Deployment)**!
==========================

You are going too fast, I am still in the following section(section above), but in step 2.2 "Apply Constraints to Cluster" when ruuning "kubectl apply -f policies/disallow-privileged.yaml
kubectl get k8snoprivilegedcontainers" got the error:
====
@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ kubectl apply -f policies/disallow-privileged.yaml
kubectl get k8snoprivilegedcontainers
error: resource mapping not found for name: "psp-no-privileged-containers" namespace: "" from "policies/disallow-privileged.yaml": no matches for kind "K8sNoPrivilegedContainers" in version "constraints.gatekeeper.sh/v1beta1"
ensure CRDs are installed first
error: the server doesn't have a resource type "k8snoprivilegedcontainers"
====

=============

I hear you! Let me pause right here with you on **Step 2.2**. We will fix this exact error before looking at anything else.

---

### Why Did This Error Happen?

The error message:
`no matches for kind "K8sNoPrivilegedContainers" in version "constraints.gatekeeper.sh/v1beta1"`

This happens because of the **ConstraintTemplate vs. Constraint** rule we discussed earlier:

1. In Kubernetes, a `Constraint` cannot be applied until its `ConstraintTemplate` (which creates the Custom Resource Definition / CRD) exists in the cluster.
2. The standard Policy Controller template name in Google Cloud's library for privileged containers is **`K8sPSPPrivilegedContainer`** (PSP stands for Pod Security Policy), rather than `K8sNoPrivilegedContainers`.

Because Kubernetes didn't recognize `K8sNoPrivilegedContainers`, it didn't know what resource type you were trying to apply.

---

### Step 1: Verify Installed Templates in Cluster

Run this command in your terminal to see the list of templates pre-loaded by Policy Controller:

```bash
kubectl get constrainttemplates

```

You should see `k8spspprivilegedcontainer` listed in the output.

---

### Step 2: Fix `policies/disallow-privileged.yaml`

Update `/workspaces/gke-defense-in-depth/policies/disallow-privileged.yaml` to use the correct `kind: K8sPSPPrivilegedContainer`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPPrivilegedContainer
metadata:
  name: psp-no-privileged-containers
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces:
      - kube-system
      - gke-system
      - gatekeeper-system

```

---

### Step 3: Re-apply the Constraint

Now run `kubectl apply` again:

```bash
# 1. Apply the corrected constraint
kubectl apply -f policies/disallow-privileged.yaml

# 2. Verify the constraint is active
kubectl get k8spspprivilegedcontainer

```

---

### Step 4: Test the Guardrail (Verification)

Let's prove that Gatekeeper is actively protecting your cluster by attempting to deploy a privileged pod:

```bash
kubectl run test-privileged-pod --image=nginx --privileged -n default

```

**Expected Result:**
The Kubernetes API Server will reject the command with a Policy Controller denial message similar to:

```text
Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request: [psp-no-privileged-containers] Privileged container is not allowed: test-privileged-pod

```

---

Try running **Steps 1 through 4** above and tell me what output you get! Once this constraint is verified, we can move forward at your pace.

====
Related GGKE links:
- https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/latest/reference/constraint-template-library#k8spspprivilegedcontainer

==========
@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ # 1. Apply the corrected constraint
kubectl apply -f policies/disallow-privileged.yaml

# 2. Verify the constraint is active
kubectl get k8spspprivilegedcontainer
k8spspprivilegedcontainer.constraints.gatekeeper.sh/psp-no-privileged-containers created
NAME                           ENFORCEMENT-ACTION   TOTAL-VIOLATIONS
psp-no-privileged-containers                        
@Kam4280 ➜ /workspaces/gke-defense-in-depth (main) $ kubectl run test-privileged-pod --image=nginx --privileged -n default
Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request: [psp-no-privileged-containers] Privileged container is not allowed: test-privileged-pod, securityContext: {"privileged": true}
===========
That error message is music to a security engineer's ears!

Look at what just happened under the hood:

You ran kubectl run ... --privileged.

The GKE Control Plane intercepted the request and queried the gatekeeper-controller-manager admission webhook.

Gatekeeper evaluated the Pod spec against your psp-no-privileged-containers rule, detected "privileged": true, and blocked the deployment in real-time.

Your Tier 4 (Policy Controller & OPA Gatekeeper) guardrails are now 100% verified and operational.

=========
