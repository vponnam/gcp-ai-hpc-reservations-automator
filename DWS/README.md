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

2. Configure Variables:  
    Open dws-calendar-capacity.sh in your preferred editor to adjust the search parameters:

    - `TPU_REGIONS` / `GPU_REGIONS`: The regions you want to scan. This can be all supported regions or regions of interest.

    - start_time_range / end_time_range: Your anticipated reservation window.

    - duration_range: The min/max length of the reservation (e.g., min=60d,max=90d).

    - other variables such as `CHIP_COUNTS` as required.

3. 📖 Usage   

 ```bash
    ./dws-calendar-capacity.sh
    
    Usage: /Users/vponnam/Documents/dws-calendar-capacity.sh [-t] [-g]
    -t    Lookup TPU capacity
    -g    Lookup GPU capacity
    Example: /Users/vponnam/Documents/dws-calendar-capacity.sh -t -g   (Runs both)
```

## Examples
### Search for both TPU and GPU:
```bash
./dws-calendar-capacity.sh -t -g
```

### Search for TPU only

```bash
./dws-calendar-capacity.sh -t
```

## 🔗 Useful Links
- [DWS Calendar Mode Overview](https://docs.cloud.google.com/compute/docs/instances/future-reservations-calendar-mode-overview)

- [TPU Calendar Mode Reservations](https://docs.cloud.google.com/tpu/docs/calendar-mode-reservation)

- [Advice API Reference](https://docs.cloud.google.com/compute/docs/instances/create-future-reservations-calendar-mode#view-availability)