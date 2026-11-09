# Cloud TPU v5e Reservations & On-Demand Provisioning Guide

This guide provides step-by-step instructions and official references for reserving and provisioning **Google Cloud TPU v5e** (`tpu_lite_podslice_v5` / `ct5lp-hightpu-*` / `v5litepod-*`) capacity using **Calendar Mode (Future Reservations)** and **On-Demand Mode**.

---

## 📋 Overview: Can TPU v5e Be Reserved with a Regular Compute Reservation?

**No.** By default, Cloud TPU v5e (`ct5lp-hightpu-*`) **cannot** be reserved using a standard Compute Engine On-Demand Reservation (`gcloud compute reservations create`). Unless your project has special internal allowlisting, the Compute Engine Reservations API returns:

```text
ERROR: (gcloud.beta.compute.reservations.create) Could not fetch resource:
 - The specified machine family is not supported for on-demand reservations.
```

Instead, Google Cloud supports the following reservation and provisioning models for **TPU v5e** (see [About Cloud TPU reservations](https://docs.cloud.google.com/tpu/docs/about-tpu-reservations)):

| Provisioning / Reservation Model | Duration | Quota Used | Best For |
| :--- | :--- | :--- | :--- |
| **DWS Calendar Mode (Future Reservation)** | 1 to 90 days | Calendar Mode / Future Reservation approval | Short-term, time-bound training, fine-tuning, or scheduled batch workloads |
| **Committed Use Discount (CUD) Reservation** | 1 or 3 years | Committed TPU quota | Continuous, steady-state production training or inference |
| **On-Demand via Queued Resources** | Pay-as-you-go | On-Demand TPU v5e (`TPU v5 Lite PodSlice chips`) | Single-host or multi-host slices that can wait in a queue for capacity |
| **On-Demand via GCE TPU VMs** | Pay-as-you-go | On-Demand TPU v5e (`TPU v5 Lite PodSlice chips`) | Single-host TPU VMs (`1t`, `4t`, `8t`) managed directly via Compute Engine |

### TPU v5e Machine Types & Accelerator Mapping

| Chips per VM | GCE Machine Type | Cloud TPU Accelerator Type | Host Topology |
| :--- | :--- | :--- | :--- |
| **1 chip** | `ct5lp-hightpu-1t` | `v5litepod-1` | Single-host (1 VM) |
| **4 chips** | `ct5lp-hightpu-4t` | `v5litepod-4` | Single-host (1 VM) |
| **8 chips** | `ct5lp-hightpu-8t` | `v5litepod-8` | Single-host (1 VM) |
| **16–256 chips** | `ct5lp-hightpu-4t` (multi-host) | `v5litepod-16` … `v5litepod-256` | Multi-host PodSlice (4 chips/VM across 4–64 VMs) |

---

## 🗓️ Part 1: TPU v5e Calendar Mode Reservation (1–90 Days)

[Dynamic Workload Scheduler (DWS) Calendar Mode](https://docs.cloud.google.com/tpu/docs/calendar-mode-reservation) lets you check future TPU v5e capacity availability up to 120 days in advance and reserve capacity for **1 to 90 days** without a multi-year commitment.

### Step 1: Check TPU v5e Availability (Advice API)

Before submitting a Calendar Mode reservation request, query the Compute Engine Advice API to find available zones and time windows.

#### Option A: Use the Repository's Automated Capacity Lookup Script
Run [`DWS/dws-calendar-capacity.sh`](../DWS/dws-calendar-capacity.sh) to scan multiple regions and chip counts for `V5E`:

```bash
cd ../DWS
./dws-calendar-capacity.sh -t
```

#### Option B: Run `gcloud beta compute advice calendar-mode` Directly
Query a specific region, chip count, and date window for TPU v5e (`--tpu-version=V5E`):

```bash
gcloud beta compute advice calendar-mode \
    --project=PROJECT_ID \
    --region=us-east1 \
    --tpu-version=V5E \
    --chip-count=64 \
    --workload-type=BATCH \
    --start-time-range="from=2026-06-01,to=2026-07-01" \
    --end-time-range="from=2026-07-15,to=2026-09-01" \
    --duration-range="min=30d,max=60d"
```

* **`--tpu-version=V5E`**: Specifies Cloud TPU v5e.
* **`--chip-count`**: Number of TPU v5e chips requested (e.g., `8`, `16`, `32`, `64`, `128`, `256`).
* **`--workload-type`**: Set to `BATCH` (for training/batch jobs) or `SERVING`.

---

### Step 2: Create the Calendar Mode Future Reservation Request

Once the Advice API returns a recommended `location` (zone), `startTime`, and `endTime`, create the Calendar Mode future reservation request:

```bash
gcloud beta compute future-reservations create v5e-calendar-fr \
    --project=PROJECT_ID \
    --zone=us-east1-b \
    --reservation-mode=CALENDAR \
    --planning-status=SUBMITTED \
    --auto-delete-auto-created-reservations \
    --require-specific-reservation \
    --reservation-name=v5e-calendar-res \
    --tpu-version=V5E \
    --chip-count=64 \
    --workload-type=BATCH \
    --start-time="2026-06-01T00:00:00Z" \
    --end-time="2026-07-01T00:00:00Z"
```

#### Key Flags Explained
* **`--reservation-mode=CALENDAR`**: Enables DWS Calendar Mode.
* **`--planning-status=SUBMITTED`**: Submits the request immediately for GCP review and approval.
* **`--auto-delete-auto-created-reservations`**: Required for Calendar Mode; automatically deletes the underlying reservation when `--end-time` is reached.
* **`--require-specific-reservation`**: Ensures only workloads that explicitly target this reservation name can consume it.
* **`--reservation-name`**: Name of the underlying reservation that Google Cloud will automatically create at `--start-time`.

---

### Step 3: Verify Future Reservation Status

Check whether your request has transitioned from `PENDING_APPROVAL` to `APPROVED` and `PROCURING`/`FULFILLED`:

```bash
gcloud beta compute future-reservations describe v5e-calendar-fr \
    --project=PROJECT_ID \
    --zone=us-east1-b \
    --format="yaml(name,planningStatus,status,timeWindow,specificSkuProperties)"
```

---

### Step 4: Consume the Calendar Mode Reservation (Create TPU v5e)

Once the reservation start time arrives and the auto-created reservation (`v5e-calendar-res`) is active, provision your TPU v5e resources using `--provisioning-model=reservation-bound`.

#### Method A: Via Cloud TPU Queued Resources (Single-Host or Multi-Host PodSlice)
```bash
gcloud alpha compute tpus queued-resources create v5e-reserved-qr \
    --project=PROJECT_ID \
    --zone=us-east1-b \
    --node-id=v5e-reserved-node \
    --accelerator-type=v5litepod-64 \
    --runtime-version=v2-alpha-tpuv5-lite \
    --reservation=projects/PROJECT_ID/zones/us-east1-b/reservations/v5e-calendar-res \
    --provisioning-model=reservation-bound
```

#### Method B: Via Compute Engine TPU VM (Single-Host `ct5lp-hightpu-*`)
```bash
gcloud compute instances create v5e-reserved-vm \
    --project=PROJECT_ID \
    --zone=us-east1-b \
    --machine-type=ct5lp-hightpu-4t \
    --image-family=ubuntu-accel-2204-amd64-tpu-v5e-v5p-v6e \
    --image-project=ubuntu-os-accelerator-images \
    --maintenance-policy=TERMINATE \
    --reservation-affinity=specific \
    --reservation=projects/PROJECT_ID/zones/us-east1-b/reservations/v5e-calendar-res \
    --provisioning-model=reservation-bound
```

---

## ⚡ Part 2: On-Demand TPU v5e Creation

When you do not have a Future Reservation or CUD, you can create TPU v5e resources on-demand using **automated polling (`reservations.sh`)**, **Cloud TPU Queued Resources**, or **Compute Engine TPU VMs**.

> [!IMPORTANT]
> **Quota Requirement:** On-demand TPU v5e creation requires sufficient **On-Demand `TPU v5 Lite PodSlice chips`** (`tpu_lite_podslice_v5`) quota in your target zone.

---

### Option 1: Automated Polling & Provisioning via `reservations.sh`

[`reservations.sh`](./reservations.sh) automates securing on-demand TPU v5e capacity in high-demand zones. When `TPU_PROVISION_MODE=auto` (default), it automatically switches from GCE Reservations to polling and provisioning labeled on-demand TPU VMs (`gce-vm`) or Queued Resources (`queued-resource`).

#### 1A. Provision 24 TPU v5e Chips (6 × `ct5lp-hightpu-4t` GCE VMs)
```bash
RESOURCE_PREFIX="vponnam" \
LABELS="prefix=vponnam,owner=vponnam,accelerator=tpu-lite-podslice-v5" \
./reservations.sh vponnam-v5e-res PROJECT_ID us-east1-b tpu_lite_podslice_v5 tpu 24
```
* Automatically maps `24` chips of `tpu_lite_podslice_v5` to **6 instances of `ct5lp-hightpu-4t`** (4 chips/VM).
* To use 8-chip VMs (`ct5lp-hightpu-8t`, 3 VMs total), prefix with `TPU_CHIPS_PER_VM=8`.

#### 1B. Provision Using Explicit Machine Type (`ct5lp-hightpu-4t`)
```bash
RESOURCE_PREFIX="vponnam" \
./reservations.sh vponnam-v5e-res PROJECT_ID us-east1-b ct5lp-hightpu-4t tpu 6
```

#### 1C. Provision via Cloud TPU Queued Resources Mode
```bash
TPU_PROVISION_MODE="queued-resource" \
RESOURCE_PREFIX="vponnam" \
./reservations.sh vponnam-v5e-qr PROJECT_ID us-east1-b v5litepod-4 tpu 6
```

---

### Option 2: Direct On-Demand Creation via Cloud TPU Queued Resources (`gcloud`)

The **Queued Resources API** is the recommended `gcloud` workflow for on-demand TPU v5e creation (required for multi-host PodSlices like `v5litepod-16` and above, and also supported for single-host slices like `v5litepod-1`, `v5litepod-4`, and `v5litepod-8`). If capacity is temporarily unavailable, the request waits in the queue until fulfilled.

#### 1. Create the On-Demand TPU v5e Queued Resource
```bash
gcloud compute tpus queued-resources create v5e-ondemand-qr \
    --project=PROJECT_ID \
    --zone=us-east1-b \
    --node-id=v5e-ondemand-node \
    --accelerator-type=v5litepod-4 \
    --runtime-version=v2-alpha-tpuv5-lite \
    --labels=owner=vponnam,env=dev
```
*(For a multi-host slice such as 16 or 64 chips, change `--accelerator-type` to `v5litepod-16` or `v5litepod-64`).*

#### 2. Monitor Queued Resource Status
```bash
gcloud compute tpus queued-resources describe v5e-ondemand-qr \
    --project=PROJECT_ID \
    --zone=us-east1-b
```
Wait until `state.state` reaches `ACTIVE`.

#### 3. SSH into the TPU v5e VM
```bash
gcloud compute tpus tpu-vm ssh v5e-ondemand-node \
    --project=PROJECT_ID \
    --zone=us-east1-b
```

#### 4. Clean Up / Delete the Queued Resource
```bash
gcloud compute tpus queued-resources delete v5e-ondemand-qr \
    --project=PROJECT_ID \
    --zone=us-east1-b \
    --force
```

---

### Option 3: Direct On-Demand Creation via Compute Engine TPU VM (`gcloud`)

For single-host TPU v5e configurations (`1`, `4`, or `8` chips), you can create a Compute Engine TPU VM directly using the `ct5lp-hightpu-*` machine family:

```bash
gcloud compute instances create v5e-ondemand-vm \
    --project=PROJECT_ID \
    --zone=us-east1-b \
    --machine-type=ct5lp-hightpu-4t \
    --image-family=ubuntu-accel-2204-amd64-tpu-v5e-v5p-v6e \
    --image-project=ubuntu-os-accelerator-images \
    --maintenance-policy=TERMINATE \
    --labels=owner=vponnam,env=dev
```

---

### Option 4: Direct On-Demand Creation via Cloud TPU VM API (`gcloud`)

You can also create an on-demand TPU v5e node directly via `gcloud compute tpus tpu-vm create`:

```bash
gcloud compute tpus tpu-vm create v5e-ondemand-tpu \
    --project=PROJECT_ID \
    --zone=us-east1-b \
    --accelerator-type=v5litepod-4 \
    --version=v2-alpha-tpuv5-lite \
    --labels=owner=vponnam,env=dev
```

---

## 🔗 Official Google Cloud Documentation References

* **TPU Reservations & Calendar Mode:**
  * [About Cloud TPU reservations](https://docs.cloud.google.com/tpu/docs/about-tpu-reservations)
  * [Request a calendar-mode future reservation for Cloud TPU](https://docs.cloud.google.com/tpu/docs/calendar-mode-reservation)
  * [Future reservations in calendar mode overview](https://docs.cloud.google.com/compute/docs/instances/future-reservations-calendar-mode-overview)
  * [View future availability using the Advice API](https://docs.cloud.google.com/compute/docs/instances/create-future-reservations-calendar-mode#view-availability)
  * [Choose a Compute Engine reservation type (Supported machine series)](https://docs.cloud.google.com/compute/docs/instances/choose-reservation-type#comparison)
* **TPU v5e Architecture & On-Demand Provisioning:**
  * [Cloud TPU v5e architecture and configurations](https://docs.cloud.google.com/tpu/docs/v5e)
  * [Manage TPU resources using Queued Resources](https://docs.cloud.google.com/tpu/docs/queued-resources)
  * [TPUs in Compute Engine (`ct5lp-*`, `ct6e-*`)](https://docs.cloud.google.com/tpu/docs/tpus-in-compute-engine)
  * [Consumption options supported by accelerator machine type](https://docs.cloud.google.com/compute/docs/accelerator-optimized-machines#consumption_option_availability_by_machine_type)
