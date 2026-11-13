#!/bin/bash
# Pools for DWS Calendar mode capacity across the regions using the advice API.
# https://docs.cloud.google.com/compute/docs/instances/create-future-reservations-calendar-mode#view-availability
# https://docs.cloud.google.com/sdk/gcloud/reference/beta/compute/advice/calendar-mode 
# https://docs.cloud.google.com/compute/docs/instances/future-reservations-calendar-mode-overview#limitations-all

set -eo pipefail

# --- Common Date & Window Defaults ---
# Dynamically defaults start-time-range to now (T) through T+60 days (UTC) so manual edits aren't required.
# Users can override via environment variables before running the script:
#   START_OFFSET_DAYS=90 ./dws-calendar-capacity.sh -g
#   START_TIME_RANGE="from=2026-12-01,to=2026-12-30" DURATION_RANGE="min=30d,max=90d" ./dws-calendar-capacity.sh -g
START_OFFSET_DAYS=${START_OFFSET_DAYS:-60}
DEFAULT_START_FROM=$(date -u +"%Y-%m-%d")
DEFAULT_START_TO=$(date -u -v+"${START_OFFSET_DAYS}"d +"%Y-%m-%d" 2>/dev/null || date -u -d "+${START_OFFSET_DAYS} days" +"%Y-%m-%d")

START_TIME_RANGE=${START_TIME_RANGE:-"from=${DEFAULT_START_FROM},to=${DEFAULT_START_TO}"}
END_TIME_RANGE=${END_TIME_RANGE:-""} # Optional: leave empty so start_time_range + duration_range determine the window
DURATION_RANGE=${DURATION_RANGE:-"min=30d,max=90d"} # Common default duration range for both TPU and GPU

# TPU Variables
# https://docs.cloud.google.com/tpu/docs/calendar-mode-reservation#limitations
declare -a TPU_REGIONS=("us-east1" "us-east5" "us-central1") # List of TPU supported regions
# declare -a TPU_REGIONS=("us-south1" "us-east5" "us-central1" "us-east1" "asia-northeast1" "europe-west4" "us-west4") # List of TPU supported regions
declare -a TPU_CHIP_COUNTS=(8 16 32 64) # Range of chip counts to look for
declare -a TPU_VERSIONS=("V5E" "V6E") # TPU chip types
TPU_Workloadtype=${TPU_Workloadtype:-"BATCH"}
start_time_range=${start_time_range:-"$START_TIME_RANGE"} # Reservation anticipated start date (defaults to T..T+60d)
end_time_range=${end_time_range:-"$END_TIME_RANGE"}       # Optional reservation anticipated end date
duration_range=${duration_range:-"$DURATION_RANGE"}       # min and max days for the reservation (defaults to min=30d,max=90d)

# For TPU capacity
lookup_dws_tpu_capacity() {
    tpu_capacity=""
    local end_time_flag=()
    if [[ -n "$end_time_range" ]]; then
        end_time_flag=("--end-time-range=$end_time_range")
    fi
    echo "--> TPU Search Window: start=[$start_time_range] duration=[$duration_range]${end_time_range:+ end=[$end_time_range]}"
    for r in "${TPU_REGIONS[@]}"
    do 
      echo "******* Looking for TPU DWS Calendar chips availability in $r *******"
      for c in "${TPU_CHIP_COUNTS[@]}"
      do
        for v in "${TPU_VERSIONS[@]}"
        do
          tpu_capacity+="$(gcloud beta compute advice calendar-mode \
            --tpu-version=$v \
            --chip-count=$c \
            --workload-type=$TPU_Workloadtype \
            --region="$r" \
            --start-time-range="$start_time_range" \
            "${end_time_flag[@]}" \
            --duration-range="$duration_range" \
            --format=json | jq -c --arg v "$v" --arg c "$c" '.[].recommendations.[].recommendationsPerSpec.spec | del(.otherLocations) | select( .location != null ) | . + {tpu_version: $v, chip_count: $c}')"
        done
      done
    done
    echo "${tpu_capacity}" | jq -s -r '["Location", "TPU_Version", "Chip_Count", "StartTime", "EndTime", "RecommendationType"] as $headers | $headers, ([$headers[] | "---------"]), (.[] | [.location, .tpu_version, .chip_count, .startTime, .endTime, .recommendationType]) | @tsv' | column -t -s $'\t'
}

# GPU Variables
# gcloud compute machine-types list --filter="name=a3-highgpu-8g" (https://docs.cloud.google.com/compute/docs/regions-zones#available)
# declare -a GPU_REGIONS=("us-south1" "europe-west4") # Target regions for H200 lookup
declare -a GPU_REGIONS=("us-south1" "us-west1" "us-east4" "us-east5" "us-central1" "us-east1" "asia-northeast1" "europe-west4" "us-west4") # List of GPU supported regions (https://docs.cloud.google.com/compute/docs/regions-zones#available).
declare -a GPU_VM_COUNTS=(2 4 6 8 10) # Range of VM counts to look for (2-10 VMs = 16-80 GPUs @ 8 GPUs/VM). Max: 80 VMs
declare -a GPU_VERSIONS=("a3-megagpu-8g" "a3-ultragpu-8g") # GPU machine types (8 GPUs per VM)
# declare -a GPU_VERSIONS=("a3-highgpu-8g" "a3-megagpu-8g" "a4-highgpu-8g" "a3-ultragpu-8g") # GPU types
gpu_start_time_range=${gpu_start_time_range:-"$START_TIME_RANGE"} # Reservation anticipated start date (defaults to T..T+60d)
gpu_end_time_range=${gpu_end_time_range:-"$END_TIME_RANGE"}       # Optional reservation anticipated end date
gpu_duration_range=${gpu_duration_range:-"$DURATION_RANGE"}       # min and max days for the reservation (defaults to min=30d,max=90d)

# For GPU capacity
# https://docs.cloud.google.com/compute/docs/regions-zones#available
lookup_dws_gpu_capacity() {
    gpu_capacity=""
    local end_time_flag=()
    if [[ -n "$gpu_end_time_range" ]]; then
        end_time_flag=("--end-time-range=$gpu_end_time_range")
    fi
    echo "--> GPU Search Window: start=[$gpu_start_time_range] duration=[$gpu_duration_range]${gpu_end_time_range:+ end=[$gpu_end_time_range]}"
    for r in "${GPU_REGIONS[@]}"
    do 
      echo "******* Looking for GPU DWS Calendar chips availability in $r *******"
      for c in "${GPU_VM_COUNTS[@]}"
      do
        for v in "${GPU_VERSIONS[@]}"
        do
          gpu_capacity+="$(gcloud beta compute advice calendar-mode \
            --machine-type=$v \
            --vm-count=$c \
            --region="$r" \
            --start-time-range="$gpu_start_time_range" \
            "${end_time_flag[@]}" \
            --duration-range="$gpu_duration_range" \
            --format=json | jq -c --arg v "$v" --arg c "$c" --arg g "$((c * 8))" '.[].recommendations.[].recommendationsPerSpec.spec | del(.otherLocations) | select( .location != null ) | . + {gpu_version: $v, vm_count: $c, gpu_count: $g}')"
        done
      done
    done
    echo "${gpu_capacity}" | jq -s -r '["Location", "GPU_Version", "VM_Count", "GPU_Count", "StartTime", "EndTime", "RecommendationType"] as $headers | $headers, ([$headers[] | "---------"]), (.[] | [.location, .gpu_version, .vm_count, .gpu_count, .startTime, .endTime, .recommendationType]) | @tsv' | column -t -s $'\t'
}

usage() {
    echo "Usage: $0 [-t] [-g]"
    echo "  -t    Lookup TPU capacity"
    echo "  -g    Lookup GPU capacity"
    echo ""
    echo "Optional Environment Variable Overrides:"
    echo "  START_OFFSET_DAYS  : Days from today (T) for default start window T..T+N (default: 60)"
    echo "  START_TIME_RANGE   : Custom start window (default: \"from=${DEFAULT_START_FROM},to=${DEFAULT_START_TO}\")"
    echo "  DURATION_RANGE     : Custom duration range for TPU & GPU (default: \"min=30d,max=90d\")"
    echo "  END_TIME_RANGE     : Optional end window constraint (default: unset)"
    echo ""
    echo "Examples:"
    echo "  $0 -t -g"
    echo "  START_TIME_RANGE=\"from=2026-12-01,to=2026-12-30\" DURATION_RANGE=\"min=30d,max=90d\" $0 -g"
    exit 1
}

# Entry Point
# If no arguments provided, show usage
if [ $# -eq 0 ]; then usage; fi

# Parse flags
while getopts "tg" opt; do
  case ${opt} in
    t ) RUN_TPU=true ;;
    g ) RUN_GPU=true ;;
    * ) usage ;;
  esac
done

# Invoke functions based on flags
if [ "$RUN_TPU" = true ]; then lookup_dws_tpu_capacity; fi
if [ "$RUN_GPU" = true ]; then lookup_dws_gpu_capacity; fi