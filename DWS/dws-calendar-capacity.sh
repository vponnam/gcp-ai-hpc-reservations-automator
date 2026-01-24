#!/bin/bash
# Pools for DWS Calendar mode capacity across the regions using the advice API.
# https://docs.cloud.google.com/compute/docs/instances/create-future-reservations-calendar-mode#view-availability
# https://docs.cloud.google.com/sdk/gcloud/reference/beta/compute/advice/calendar-mode 
# https://docs.cloud.google.com/compute/docs/instances/future-reservations-calendar-mode-overview#limitations-all

set -eo pipefail

#TPU Variables
# https://docs.cloud.google.com/tpu/docs/calendar-mode-reservation#limitations
declare -a TPU_REGIONS=("us-south1" "us-east5" "us-central1" "us-east1" "asia-northeast1" "europe-west4" "us-west4") # List of TPU supported regions
declare -a TPU_CHIP_COUNTS=(64 128 256 512) # Range of chip counts to look for
declare -a TPU_VERSIONS=("V5E" "V6E") # TPU chip types
TPU_Workloadtype="BATCH"
start_time_range="from=2026-01-24,to=2026-06-25" # Reservation anticipated start date
end_time_range="from=2026-03-25,to=2026-06-25" # Reservation anticipated end date
duration_range="min=60d,max=90d" # min and max days for the reservation

# For TPU capacity
lookup_dws_tpu_capacity() {
    tpu_capacity=""
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
            --end-time-range="$end_time_range" \
            --duration-range="$duration_range" \
            --format=json | jq -c --arg v "$v" --arg c "$c" '.[].recommendations.[].recommendationsPerSpec.spec | del(.otherLocations) | select( .location != null ) | . + {tpu_version: $v, chip_count: $c}')"
        done
      done
    done
    echo "${tpu_capacity}" | jq -s -r '["Location", "TPU_Version", "Chip_Count", "StartTime", "EndTime", "RecommendationType"] as $headers | $headers, ([$headers[] | "---------"]), (.[] | [.location, .tpu_version, .chip_count, .startTime, .endTime, .recommendationType]) | @tsv' | column -t -s $'\t'
}

# GPU Variables
# gcloud compute machine-types list --filter="name=a3-highgpu-8g" (https://docs.cloud.google.com/compute/docs/regions-zones#available)
declare -a GPU_REGIONS=("us-west1" "us-east4" "us-east5" "us-central1" "us-east1" "asia-northeast1" "europe-west4" "us-west4") #List of GPU supported regions(https://docs.cloud.google.com/compute/docs/regions-zones#available).
declare -a GPU_VM_COUNTS=(16 48 80) #range of chip counts to look for. Max: 80 VMs
declare -a GPU_VERSIONS=("a3-highgpu-8g" "a3-megagpu-8g" "a4-highgpu-8g" "a3-ultragpu-8g") # GPU types
gpu_start_time_range="from=2026-01-24,to=2026-06-25" # Reservation anticipated start date
gpu_end_time_range="from=2026-03-25,to=2026-06-25" # Reservation anticipated end date
gpu_duration_range="min=90d,max=90d" #min and max days for the reservation

# For GPU capacity
# https://docs.cloud.google.com/compute/docs/regions-zones#available
lookup_dws_gpu_capacity() {
    gpu_capacity=""
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
            --start-time-range="$start_time_range" \
            --end-time-range="$end_time_range" \
            --duration-range="$duration_range" \
            --format=json | jq -c --arg v "$v" --arg c "$c" '.[].recommendations.[].recommendationsPerSpec[].spec | del(.otherLocations) | select( .location != null ) | . + {gpu_version: $v, vm_count: $c}')"
        done
      done
    done
    echo $gpu_capacity
    # echo "${gpu_capacity}" | jq -s -r '["Location", "GPU_Version", "VM_Count", "StartTime", "EndTime", "RecommendationType"] as $headers | $headers, ([$headers[] | "---------"]), (.[] | [.location, .gpu_version, .vm_count, .startTime, .endTime, .recommendationType]) | @tsv' | column -t -s $'\t'
}

usage() {
    echo "Usage: $0 [-t] [-g]"
    echo "  -t    Lookup TPU capacity"
    echo "  -g    Lookup GPU capacity"
    echo "  Example: $0 -t -g   (Runs both)"
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