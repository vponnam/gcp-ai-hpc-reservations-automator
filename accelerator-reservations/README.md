# GCP Accelerator On-Demand Reservation Automator
> Disclaimer: This project was inspired by original scripts developed by my colleagues. I am capturing this here for easy access and do not claim original authorship of the logic.

This script automates the process of securing [On-Demand Reservations](https://docs.cloud.google.com/compute/docs/instances/reservations-overview) in Google Cloud. It is particularly useful for high-demand resources like GPUs (H100s, L4s, etc.) where capacity is often limited.

[onDemand resrvations](https://docs.cloud.google.com/compute/docs/instances/reservations-overview) can either be local to the hosting project or shared across child projects.

## 🚀 Why This Exists
Securing GPU capacity in high-demand regions can be a "race to the finish." Doing this manually in the console is inefficient. This script:

*   **Polls the API:** Regularly checks for available capacity.
*   **Incremental Growth:** Upsizes your reservation one VM at a time as capacity becomes available.
*   **Automation:** Allows you to focus on your workloads rather than manually retrying failed capacity requests.

Once your desired count is met, you can [attach a Commitment (CUD)](https://docs.cloud.google.com/compute/docs/instances/reservations-with-commitments) to the reservation to benefit from significant cost savings.

---

## 🛠️ Features

- [x] Supports **Shared Reservations** across multiple projects.
- [x] **Configurable Backoff:** Adjustable retry rates to avoid API rate limiting.
- [x] **Incremental Scaling:** Controlled via the `INCREMENT` flag to snag capacity as it opens up.
- [x] **Idempotent:** Becomes a `noop` (no-operation) once the target count is reached.

---

## 🏁 Getting Started

### Prerequisites

Before running the script, ensure you have:

1.  **IAM Permissions:** Sufficient rights to create reservations and update `OrgPolicy` (if creating shared reservations).
2.  **Quotas:** Ensure your project has the necessary GPU and Compute quotas increased in both host and child projects.
3.  **Authentication:** Run `gcloud auth login` and set your active project.

### Usage

1.  **Clone/Copy** the script to your environment.
2.  **Make it executable:** 
    ```bash
    chmod +x reservations.sh
    ```
3.  **Execute the command:**
    ```bash
    ./reservations.sh <name> <project> <zone> <machine-type> <accelerator-config> <count>
    ```
    **Example:**
    To reserve 5 `a3-highgpu-8g` nodes (each with 8 H100 GPUs) in `us-central1-a`:
    ```bash
    ./reservations.sh res-h100-prod my-project-id us-central1-a a3-highgpu-8g "type=nvidia-h100-80gb,count=8" 5
4. For local reservations drop the `--share-setting` and `--share-with` flags from the create reservations command.

It is recommended to run this in a persistent session to allow it to run over several hours or days:
* Screen/Tmux: tmux new -s gcp-res './reservations.sh ...'
* Background: Use nohup ./reservations.sh ... & to keep it running after logout.

## 💡 Important Notes
1. **Costs**: On-demand reservations are charged at standard on-demand rates as soon as they are successfully provisioned.

2. **Workload Ramping**: Because the script fills the reservation incrementally, you should ramp up your workloads as the chips become available to avoid idle costs.

3. **Flexibility**: Prior to attaching a CUD, reservations can be deleted at any time. This allows you to run the script in multiple regions in parallel and delete the "losing" regions once your primary goal is met.

# References
* [Consumption options supported by machine type](https://docs.cloud.google.com/compute/docs/accelerator-optimized-machines#consumption_option_availability_by_machine_type)
* [GPU availability by regions](https://docs.cloud.google.com/compute/docs/regions-zones/gpu-regions-zones#view-using-table)
* [onDemand reservation types and configs](https://docs.cloud.google.com/compute/docs/instances/reservations-overview)
* [CUD attachment to reservations](https://docs.cloud.google.com/compute/docs/instances/reservations-with-commitments)
* [Reservation sharing best practices](https://docs.cloud.google.com/compute/docs/instances/best-practices-shared-reservations)
