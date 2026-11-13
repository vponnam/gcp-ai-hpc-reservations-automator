# GCP On-Demand Compute & Accelerator Reservation Automator
> Disclaimer: This project was inspired by original scripts developed by my colleagues. I am capturing this here for easy access and do not claim original authorship of the logic.

This script automates the process of securing [On-Demand Reservations](https://docs.cloud.google.com/compute/docs/instances/reservations-overview) and on-demand accelerator capacity in Google Cloud. It is particularly useful for securing high-demand resources like GPUs (H100s, L4s, RTX Pro 6000s), Cloud TPUs (TPU v6e Trillium, v5p, v5e, v3, TPU7x), as well as CPU machine types (N1, N2, C3, etc.) with optional Local SSD (LSSD) storage attachments.

[On-Demand Reservations](https://docs.cloud.google.com/compute/docs/instances/reservations-overview) can either be local to the hosting project or shared across multiple child projects.

## 🚀 Why This Exists
Securing compute, GPU, and TPU capacity in high-demand zones can be challenging during peak utilization periods. Attempting this manually in the Google Cloud Console or running one-off commands is inefficient. This automation script provides:

* **Automated Polling:** Continuously checks for open capacity in your specified zone.
* **Incremental Scaling:** Upsizes your reservation incrementally as capacity becomes available without failing out.
* **Versatile Workflows:** Seamlessly handles standard CPU-only instances, complex GPU setups, Cloud TPU slices (`ct6e-*`, `ct5p-*`, `ct5lp-*`, `ct3-*`, or shorthands like `v6e-4`), Local SSD storage attachments, resource prefixing/labeling, and shared multi-project capacity pooling.
* **Idempotent Execution:** Automatically terminates as a clean no-op once your target instance count is satisfied.

Once your desired count is met, you can [attach a Committed Use Discount (CUD)](https://docs.cloud.google.com/compute/docs/instances/reservations-with-commitments) to the reservation to benefit from significant cost savings while guaranteeing availability.

---

## 🛠️ Features
- [x] **Universal Machine Type Support:** Compatible with standard CPU machine types, accelerator-optimized GPU node types, and Cloud TPU machine types (`ct6e-standard-*`, `ct5p-hightpu-*`, `ct5lp-hightpu-*`, `ct3-hightpu-*`, or shorthand `v6e-1`, `v6e-4`, `v6e-8`).
- [x] **Intelligent TPU On-Demand Fallback:** Automatically detects TPU families (such as TPU v6e `ct6e-*`) where the GCE Specific-SKU On-Demand Reservations API is restricted by GCP platform limits and seamlessly falls back to polling on-demand GCE TPU VMs (`gce-vm`) or Cloud TPU Queued Resources (`queued-resource`).
- [x] **Resource Prefixing & Labeling:** Enforces naming prefixes (`RESOURCE_PREFIX`) and attaches labels (`LABELS`) and Resource Manager tags (`RESOURCE_MANAGER_TAGS`) across reservations, TPU VMs, and Queued Resources.
- [x] **Local SSD (LSSD) Attachment:** Supports pairing high-speed SCSI or NVMe scratch drives directly to reserved instances.
- [x] **Shared Reservations:** Share secured capacity across multiple child projects from a central host project.
- [x] **Configurable Retry Mechanics:** Customize retry frequency, increment steps, and attempt caps via environment variables to avoid API rate limiting or infinite test loops.

---

## 🏁 Getting Started

### Prerequisites
1. **IAM Permissions:** Ensure your identity has compute reservation permissions (and `OrgPolicy` modification rights if managing shared reservations).
2. **Quotas:** Verify your project has sufficient Compute Engine vCPU, GPU, TPU (`TPUS_PER_TPU_FAMILY`), and Local SSD quota in the target zone.
3. **Authentication:** Authenticate using `gcloud auth login` and set your active billing project.

### Usage Syntax
Make the script executable before running your initial task:
```bash
chmod +x reservations.sh
```

#### Command Arguments
The script accepts two positional argument formats depending on whether you are attaching discrete GPU accelerators or reserving integrated TPU/CPU machine types:

* **GPU / TPU / Accelerator Reservations (6 arguments):**
  ```bash
  ./reservations.sh <name> <project-id> <zone> <machine-type> "<accelerator-config|tpu|none>" <count>
  ```
* **CPU-Only or Integrated TPU Reservations (5 arguments, or 6 with `tpu`/`none`):**
  ```bash
  ./reservations.sh <name> <project-id> <zone> <machine-type-or-tpu-shorthand> <count>
  # Alternatively:
  ./reservations.sh <name> <project-id> <zone> <machine-type-or-tpu-shorthand> tpu <count>
  ```

| Argument | Description | Example Value |
| :--- | :--- | :--- |
| `<name>` | Unique identifier for your GCP reservation / TPU pool | `vponnam-v5e-res` or `prod-h100-pool` |
| `<project-id>` | GCP hosting Project ID | `my-gcp-project-id` |
| `<zone>` | GCP target zone where capacity will be reserved | `us-east1-b`, `us-east1-d`, or `us-central1-a` |
| `<machine-type>` | GCE instance sizing, TPU family (`tpu_lite_podslice_v5`), or shorthand (`v5e-4`, `v6e-4`) | `tpu_lite_podslice_v5`, `ct5lp-hightpu-4t`, `ct6e-standard-4t`, `a3-highgpu-8g` |
| `<accelerator-config>` | Accelerator key-value pair, `tpu` / `tpu_lite_podslice_v5` for TPUs, or `none` for CPU | `tpu` or `type=nvidia-h100-80gb,count=8` |
| `<count>` | Target total VM instances (or total TPU chips when `<machine-type>` is `tpu_lite_podslice_v5`) | `24` (chips) or `6` (VMs) |

---

### Optional Environment Configurations
You can modify behavior dynamically without editing code by prefixing environment variables before the script invocation:

| Environment Variable | Default Value | Purpose & Example |
| :--- | :--- | :--- |
| `RESOURCE_PREFIX` | Empty (disabled) | Prepends `<prefix>-` to `<name>` if not already present and defaults `LABELS="prefix=<prefix>,owner=<prefix>"`: `RESOURCE_PREFIX="vponnam"` |
| `LABELS` | Empty (or derived from `RESOURCE_PREFIX`) | Comma-separated `key=value` labels applied to TPU VMs/Queued Resources and reservation description: `LABELS="prefix=vponnam,owner=vponnam,env=test"` |
| `RESOURCE_MANAGER_TAGS` | Empty (disabled) | Resource Manager tags attached to GCE reservations: `RESOURCE_MANAGER_TAGS="tagKeys/123=tagValues/456"` |
| `TPU_CHIPS_PER_VM` | `4` (for `tpu_lite_podslice_v5`) | Chips per TPU VM (`1`, `4`, or `8`) when specifying `tpu_lite_podslice_v5` by total chip count |
| `TPU_PROVISION_MODE` | `auto` | Controls TPU on-demand strategy: `auto` (tries GCE Reservation first, then falls back to `gce-vm`), `reservation`, `gce-vm`, or `queued-resource` |
| `LOCAL_SSD` (or `LSSD`) | Empty (disabled) | Attaches local scratch disks: `LOCAL_SSD="interface=nvme,size=375,count=4"` |
| `RESERVATION_CHILD_PROJECTS` | Empty (disabled) | Comma-separated list of consumer project IDs: `RESERVATION_CHILD_PROJECTS="child-app-1,child-app-2"` |
| `RETRY_RATE` | `60` | Delay in seconds between API polling loops |
| `INCREMENT` | `2` | Number of instances to add per upsize request |
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

### 5. On-Demand Cloud TPU v5e PodSlice (`tpu_lite_podslice_v5`) — Reserve 24 Chips in `us-east1-b`
> 📄 **Dedicated Guide:** See [TPU-v5e-Reservations.md](./TPU-v5e-Reservations.md) for complete instructions on **TPU v5e Calendar Mode (Future Reservations)** and **On-Demand creation**.

Reserve **24 `tpu_lite_podslice_v5` (TPU v5e PodSlice) chips** in `us-east1-b` with `vponnam` resource prefixing and labels:

```bash
# Option A: Specify tpu_lite_podslice_v5 directly with total chip count (24 chips -> 6 ct5lp-hightpu-4t VMs @ 4 chips/VM)
RESOURCE_PREFIX="vponnam" \
LABELS="prefix=vponnam,owner=vponnam,accelerator=tpu-lite-podslice-v5" \
./reservations.sh vponnam-v5e-res my-project us-east1-b tpu_lite_podslice_v5 tpu 24

# Option B: Specify explicit GCE TPU machine type ct5lp-hightpu-4t (6 VMs x 4 chips/VM = 24 tpu_lite_podslice_v5 chips)
RESOURCE_PREFIX="vponnam" \
LABELS="prefix=vponnam,owner=vponnam,accelerator=tpu-lite-podslice-v5" \
./reservations.sh vponnam-v5e-res my-project us-east1-b ct5lp-hightpu-4t tpu_lite_podslice_v5 6

# Option C: Use 8-chip VMs (3 ct5lp-hightpu-8t VMs x 8 chips/VM = 24 tpu_lite_podslice_v5 chips)
TPU_CHIPS_PER_VM=8 \
RESOURCE_PREFIX="vponnam" \
./reservations.sh vponnam-v5e-res my-project us-east1-b tpu_lite_podslice_v5 tpu 24
```
* **Explanation:** When `tpu_lite_podslice_v5` is passed as the 4th argument, the script interprets `<count>` (`24`) as the target total number of `tpu_lite_podslice_v5` chips and automatically maps it to **6 instances of `ct5lp-hightpu-4t`** (4 chips per VM, configurable via `TPU_CHIPS_PER_VM=1|4|8`).

---

### 6. On-Demand Cloud TPU v6e (Trillium) Reservation & Capacity Polling in `us-east1-d`
Reserve **1 TPU v6e (`ct6e-standard-4t` / `v6e-4`, 4 chips) instance** in `us-east1-d` with `vponnam` resource prefixing and labels:

```bash
RESOURCE_PREFIX="vponnam" \
LABELS="prefix=vponnam,owner=vponnam,accelerator=tpu-v6e" \
./reservations.sh vponnam-v6e-res my-project us-east1-d ct6e-standard-4t tpu 1
```
*(You can also pass the shorthand `v6e-1`, `v6e-4`, or `v6e-8` as the 4th argument).*

> [!NOTE]
> **GCP Platform Behavior for TPU On-Demand Reservations:**
> Google Cloud's Compute Engine Specific-SKU On-Demand Reservations API (`gcloud compute reservations create`) supports legacy TPU machine types (such as `ct3-hightpu-4t`), while newer TPU PodSlice families (`ct5lp-*` / `tpu_lite_podslice_v5`, `ct6e-*`, `ct5p-*`, `tpu7x-*`) require Calendar Mode Future Reservations or CUDs unless the project is specifically allowlisted.
> When `TPU_PROVISION_MODE=auto` (default), `reservations.sh` first attempts `gcloud beta compute reservations create` and, if the machine family is rejected by the GCE On-Demand Reservations API, automatically switches to polling and creating labeled on-demand Compute Engine TPU VMs (`gce-vm`) or Cloud TPU Queued Resources (`TPU_PROVISION_MODE=queued-resource`).

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
* [Choose a reservation type (Supported machine series comparison)](https://cloud.google.com/compute/docs/instances/choose-reservation-type#comparison)
* [About Cloud TPU reservations](https://cloud.google.com/tpu/docs/about-tpu-reservations)
* [TPUs in Compute Engine (`ct6e-standard-*`)](https://cloud.google.com/tpu/docs/tpus-in-compute-engine)
* [GPU availability by regions and zones](https://docs.cloud.google.com/compute/docs/regions-zones/gpu-regions-zones#view-using-table)
* [On-Demand reservation types and configurations](https://docs.cloud.google.com/compute/docs/instances/reservations-overview)
* [Local SSD documentation & machine type constraints](https://cloud.google.com/compute/docs/disks/local-ssd)
* [CUD attachment to reservations](https://docs.cloud.google.com/compute/docs/instances/reservations-with-commitments)
* [Reservation sharing best practices](https://docs.cloud.google.com/compute/docs/instances/best-practices-shared-reservations)
