# GCP DWS Calendar Capacity Lookup
This script automates the process of querying the Google Cloud Advice API to find Accelerator capacity availability in [DWS Calendar Mode](https://docs.cloud.google.com/compute/docs/instances/future-reservations-calendar-mode-overview).

Instead of manual queries, this script iterates through multiple regions, chip types, and counts to provide a consolidated table of available Future Reservation windows.

## 🚀 Overview
Finding TPU and GPU capacity for Batch workloads can be challenging. This script provides critical insight into the StartTime and EndTime windows where Google Cloud has possible availability for placement. This is a snapshot only and approvals process follow [Request lifecycle](https://docs.cloud.google.com/compute/docs/instances/future-reservations-calendar-mode-overview#lifecycle)

## Sample Output

```
Location                 TPU_Version  Chip_Count  StartTime             EndTime               RecommendationType
---------                ---------    ---------   ---------             ---------             ---------
zones/us-east5-a         V6E          64          2026-01-24T22:37:22Z  2026-04-24T22:37:22Z  FUTURE_RESERVATION
zones/us-east5-a         V6E          128         2026-01-24T22:37:24Z  2026-04-24T22:37:24Z  FUTURE_RESERVATION
zones/us-east5-a         V6E          256         2026-01-24T22:37:26Z  2026-04-24T22:37:26Z  FUTURE_RESERVATION
zones/us-east5-a         V6E          512         2026-04-17T06:00:00Z  2026-06-25T05:00:00Z  FUTURE_RESERVATION
zones/us-east1-d         V6E          64          2026-02-20T19:00:00Z  2026-05-21T19:00:00Z  FUTURE_RESERVATION
zones/us-east1-d         V6E          128         2026-04-05T21:00:00Z  2026-06-25T05:00:00Z  FUTURE_RESERVATION
zones/asia-northeast1-b  V6E          64          2026-01-24T22:37:54Z  2026-04-24T22:37:54Z  FUTURE_RESERVATION
zones/asia-northeast1-b  V6E          128         2026-01-24T22:37:56Z  2026-04-24T22:37:56Z  FUTURE_RESERVATION
zones/asia-northeast1-b  V6E          256         2026-01-24T22:37:59Z  2026-04-24T22:37:59Z  FUTURE_RESERVATION
zones/asia-northeast1-b  V6E          512         2026-03-14T08:30:00Z  2026-06-12T08:30:00Z  FUTURE_RESERVATION
zones/europe-west4-b     V5E          64          2026-01-24T22:38:03Z  2026-04-24T22:38:03Z  FUTURE_RESERVATION
zones/europe-west4-b     V5E          128         2026-01-24T22:38:05Z  2026-04-24T22:38:05Z  FUTURE_RESERVATION
zones/europe-west4-b     V5E          256         2026-01-24T22:38:08Z  2026-04-24T22:38:08Z  FUTURE_RESERVATION
zones/europe-west4-b     V5E          512         2026-02-23T09:59:00Z  2026-05-24T09:59:00Z  FUTURE_RESERVATION
```

## 🛠 Prerequisites
- Google Cloud SDK (gcloud): Ensure you have the gcloud CLI installed and authenticated.

- Beta Component: You may need to install the beta components: `gcloud components install beta`.

- JQ: This script uses `jq` for JSON processing.
    ```bash
    # macOS
    brew install jq

    # Ubuntu/Debian
    sudo apt-get install jq
    ```

## Execution
1. Clone the repository:
    ```bash
    git clone https://github.com/vponnam/cloud-samples.git && cd cloud-samples/DWS
    ```

2. **Default Behavior & Optional Variable Overrides:**  
    By default, `dws-calendar-capacity.sh` dynamically sets the reservation start window from **today (`T`) to `T+60 days`** (UTC) so you can run the script immediately without manually updating hardcoded dates each time.

    You can override the defaults at runtime via environment variables (without editing the script) or adjust the region/shape arrays directly in `dws-calendar-capacity.sh`:

    | Variable | Default Value | Description |
    | :--- | :--- | :--- |
    | `START_OFFSET_DAYS` | `60` | Number of days from today (`T`) used to compute the default `from=T,to=T+N` start window |
    | `START_TIME_RANGE` | `from=<T>,to=<T+60d>` | Explicit start window override (e.g., `from=2026-12-01,to=2026-12-30`). Can also be set separately via `start_time_range` (TPU) or `gpu_start_time_range` (GPU) |
    | `DURATION_RANGE` | `min=30d,max=90d` | Reservation duration range override for both TPU and GPU (e.g., `min=60d,max=90d`). Can also be set via `duration_range` or `gpu_duration_range` |
    | `END_TIME_RANGE` | Empty *(auto-derived)* | Optional end-time constraint (e.g., `from=2027-03-01,to=2027-04-15`). Omitted by default so `START_TIME_RANGE` + `DURATION_RANGE` determine the window |
    | `TPU_REGIONS` / `GPU_REGIONS` | Configured in script | Regions scanned for TPU and GPU capacity |
    | `TPU_CHIP_COUNTS` / `GPU_VM_COUNTS` | Configured in script | Chip counts (TPU) or VM counts (GPU) to query |

3. 📖 **Usage**   

 ```bash
    ./dws-calendar-capacity.sh
    
    Usage: ./dws-calendar-capacity.sh [-t] [-g]
      -t    Lookup TPU capacity
      -g    Lookup GPU capacity

    Optional Environment Variable Overrides:
      START_OFFSET_DAYS  : Days from today (T) for default start window T..T+N (default: 60)
      START_TIME_RANGE   : Custom start window (default: "from=<T>,to=<T+60d>")
      DURATION_RANGE     : Custom duration range for TPU & GPU (default: "min=30d,max=90d")
      END_TIME_RANGE     : Optional end window constraint (default: unset)
```

## Examples
### Search for both TPU and GPU (using dynamic `T` to `T+60d` defaults):
```bash
./dws-calendar-capacity.sh -t -g
```

### Search for TPU or GPU only:
```bash
./dws-calendar-capacity.sh -t
./dws-calendar-capacity.sh -g
```

### Override the start date window or lookahead offset via environment variables:
```bash
# Override with a custom start window and duration
START_TIME_RANGE="from=2026-12-01,to=2026-12-30" DURATION_RANGE="min=30d,max=90d" ./dws-calendar-capacity.sh -g

# Adjust the dynamic lookahead window from T+60d to T+90d
START_OFFSET_DAYS=90 ./dws-calendar-capacity.sh -g
```

## 🔗 Useful Links
- [DWS Calendar Mode Overview](https://docs.cloud.google.com/compute/docs/instances/future-reservations-calendar-mode-overview)

- [TPU Calendar Mode Reservations](https://docs.cloud.google.com/tpu/docs/calendar-mode-reservation)

- [Advice API Reference](https://docs.cloud.google.com/compute/docs/instances/create-future-reservations-calendar-mode#view-availability)