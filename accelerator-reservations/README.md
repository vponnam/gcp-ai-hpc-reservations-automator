# GCP On-Demand Compute & Accelerator Reservation Automator
> Disclaimer: This project was inspired by ideas shared by my colleagues. The code is independently maintained; I want to be transparent in acknowledging that I do not claim credit for the original concept as a sign of respect.

This script automates the process of securing [On-Demand Reservations](https://docs.cloud.google.com/compute/docs/instances/reservations-overview) in Google Cloud. It is particularly useful for securing high-demand resources like GPUs (H100s, L4s, RTX Pro 6000s) as well as CPU machine types (N1, N2, C3, etc.) with optional Local SSD (LSSD) storage attachments.

[On-Demand Reservations](https://docs.cloud.google.com/compute/docs/instances/reservations-overview) can either be local to the hosting project or shared across multiple child projects.

## 🚀 Why This Exists
Securing compute and GPU capacity in high-demand zones can be challenging during peak utilization periods. Attempting this manually in the Google Cloud Console or running one-off commands is inefficient. This automation script provides:

* **Automated Polling:** Continuously checks for open capacity in your specified zone.
* **Incremental Scaling:** Upsizes your reservation incrementally as capacity becomes available without failing out.
* **Versatile Workflows:** Seamlessly handles standard CPU-only instances, complex GPU setups, Local SSD storage attachments, and shared multi-project capacity pooling.
* **Idempotent Execution:** Automatically terminates as a clean no-op once your target instance count is satisfied.

Once your desired count is met, you can [attach a Committed Use Discount (CUD)](https://docs.cloud.google.com/compute/docs/instances/reservations-with-commitments) to the reservation to benefit from significant cost savings while guaranteeing availability.

---

## 🛠️ Features
- [x] **Universal Machine Type Support:** Compatible with standard CPU machine types as well as accelerator-optimized GPU node types.
- [x] **Local SSD (LSSD) Attachment:** Supports pairing high-speed SCSI or NVMe scratch drives directly to reserved instances.
- [x] **Shared Reservations:** Share secured capacity across multiple child projects from a central host project.
- [x] **Configurable Retry Mechanics:** Customize retry frequency, increment steps, and attempt caps via environment variables to avoid API rate limiting or infinite test loops.

---

## 🏁 Getting Started

### Prerequisites
1. **IAM Permissions:** Ensure your identity has compute reservation permissions (and `OrgPolicy` modification rights if managing shared reservations).
2. **Quotas:** Verify your project has sufficient Compute Engine vCPU, GPU, and Local SSD quota in the target zone.
3. **Authentication:** Authenticate using `gcloud auth login` and set your active billing project.

### Usage Syntax
Make the script executable before running your initial task:
```bash
chmod +x reservations.sh
```

#### Command Arguments
The script accepts two positional argument formats depending on whether you are attaching discrete GPU accelerators:

* **GPU / Accelerator Reservations (6 arguments):**
  ```bash
  ./reservations.sh <name> <project-id> <zone> <machine-type> "<accelerator-config>" <count>
  ```
* **CPU-Only Reservations (5 arguments, or 6 with `none`):**
  ```bash
  ./reservations.sh <name> <project-id> <zone> <machine-type> <count>
  # Alternatively:
  ./reservations.sh <name> <project-id> <zone> <machine-type> none <count>
  ```

| Argument | Description | Example Value |
| :--- | :--- | :--- |
| `<name>` | Unique identifier for your GCP reservation | `prod-h100-pool` |
| `<project-id>` | GCP hosting Project ID | `my-gcp-project-id` |
| `<zone>` | GCP target zone where capacity will be reserved | `us-central1-a` |
| `<machine-type>` | Google Compute Engine instance sizing | `a3-highgpu-8g` or `n1-standard-16` |
| `<accelerator-config>` | Accelerator key-value pair, or `none` for CPU instances | `type=nvidia-h100-80gb,count=8` |
| `<count>` | Target total number of VM instances to reserve | `5` |

---

### Optional Environment Configurations
You can modify behavior dynamically without editing code by prefixing environment variables before the script invocation:

| Environment Variable | Default Value | Purpose & Example |
| :--- | :--- | :--- |
| `LOCAL_SSD` (or `LSSD`) | Empty (disabled) | Attaches local scratch disks: `LOCAL_SSD="interface=nvme,size=375,count=4"` |
| `RESERVATION_CHILD_PROJECTS` | Empty (disabled) | Comma-separated list of consumer project IDs: `RESERVATION_CHILD_PROJECTS="child-app-1,child-app-2"` |
| `RETRY_RATE` | `60` | Delay in seconds between API polling loops |
| `INCREMENT` | `1` | Number of instances to add per upsize request |
| `MAX_ATTEMPTS` | `0` (Infinite loop) | Maximum failed retry attempts before stopping (ideal for scripts/CI testing) |

---

## 📚 Real-World Examples

### 1. Standard CPU Reservation
Reserve **2 instances** of an `n1-standard-16` CPU machine in `us-central1-a`:

```bash
./reservations.sh res-cpu-backend my-project us-central1-a n1-standard-16 2
```
* **Explanation:** Continually attempts to reserve capacity in project `my-project` in zone `us-central1-a` until exactly 2 `n1-standard-16` machines are locked in. Since no accelerator configuration is passed, it intelligently formats the request for general computer capacity without extra GPU parameters.

---

### 2. High-Performance GPU Pool (NVIDIA H100)
Reserve **5 nodes** of `a3-highgpu-8g` (each carrying 8 NVIDIA H100 80GB GPUs) in `us-central1-a`:

```bash
./reservations.sh res-h100-training my-project us-central1-a a3-highgpu-8g "type=nvidia-h100-80gb,count=8" 5
```
* **Explanation:** Targets dedicated accelerator clusters for heavy model training or LLM serving. If the zone currently lacks full capacity for all 5 nodes, the script captures existing availability 1 machine at a time and loops automatically every 60 seconds until all 5 nodes are safely provisioned.

---

### 3. GPU Workload with Local SSD Attachments (LSSD)
Reserve **1 Graphics-Optimized `g4-standard-48` instance** paired with 1 `nvidia-rtx-pro-6000` GPU and **4 high-speed NVMe Local SSDs** in `us-south1-a`:

```bash
LOCAL_SSD="interface=nvme,size=375,count=4" \
./reservations.sh res-gpu-lssd my-project us-south1-a g4-standard-48 "type=nvidia-rtx-pro-6000,count=1" 1
```
> [!IMPORTANT]
> **Machine-Type LSSD Pairing Rules:** Certain machine configurations enforce hardware-specific interface and quantity boundaries for Local SSDs. For example, Google Cloud Graphics Optimized `g4` families reject SCSI interfaces and require NVMe (`interface=nvme`) with fixed disk counts (e.g., exactly 4 LSSDs for `g4-standard-48`). Always consult GCP machine specs if Local SSD attachment attempts return validation errors.

---

### 4. Multi-Project Shared Reservation
Reserve **10 L4 GPU instances** in a host project and expose the reserved capacity to two independent downstream application projects (`client-prod-app` and `analytics-engine-app`):

```bash
RESERVATION_CHILD_PROJECTS="client-prod-app,analytics-engine-app" \
./reservations.sh shared-l4-pool my-host-project us-central1-a g2-standard-8 "type=nvidia-l4,count=1" 10
```
* **Explanation:** Centralizes capacity management within `my-host-project` while allowing workloads spinning up in `client-prod-app` and `analytics-engine-app` to automatically consume these reserved instances without managing their own separate pools.

---

## 💡 Best Practices & Operational Notes
1. **Background Execution:** For large capacity targets in high-demand zones, execute inside a persistent session:
   * **Tmux / Screen:** `tmux new -s gcp-res './reservations.sh ...'`
   * **Nohup:** `nohup ./reservations.sh ... > reservation.log 2>&1 &`
2. **Immediate Cost Incurrence:** On-demand reservations start charging standard compute rates the moment capacity is successfully provisioned—regardless of whether active Virtual Machines are spun up inside them.
3. **Workload Ramping:** Configure autoscaling groups or deployment pipelines to dynamically ramp workloads as instances are snagged by the script to maximize hardware efficiency and eliminate idle overhead.
4. **Regional Flexibility:** Because reservations can be deleted at any time before attaching a Commitment (CUD), you can run parallel polling tasks across multiple candidate zones (e.g., `us-central1-a`, `us-east5-a`) and delete the unused pools once your primary zone successfully secures capacity.

---

## References
* [Consumption options supported by machine type](https://docs.cloud.google.com/compute/docs/accelerator-optimized-machines#consumption_option_availability_by_machine_type)
* [GPU availability by regions and zones](https://docs.cloud.google.com/compute/docs/regions-zones/gpu-regions-zones#view-using-table)
* [On-Demand reservation types and configurations](https://docs.cloud.google.com/compute/docs/instances/reservations-overview)
* [Local SSD documentation & machine type constraints](https://cloud.google.com/compute/docs/disks/local-ssd)
* [CUD attachment to reservations](https://docs.cloud.google.com/compute/docs/instances/reservations-with-commitments)
* [Reservation sharing best practices](https://docs.cloud.google.com/compute/docs/instances/best-practices-shared-reservations)
