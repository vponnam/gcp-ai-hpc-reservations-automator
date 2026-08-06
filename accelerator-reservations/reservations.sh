#!/bin/bash
# Retrying Reservations Script - CPU, GPU, Local SSD & Shared Reservation Support
#
# Creates a compute reservation if it doesn't exist, then incrementally
# increases its size until the desired count is met. It retries
# on failure. Supports both CPU-only and GPU/Accelerator reservations,
# Local SSD (LSSD) attachments, and Shared Reservations across projects.
# orgPolicy for shared allowing reservations: https://docs.cloud.google.com/compute/docs/instances/manage-shared-reservations-creation#allow-restrict-projects

# --- Command-line Arguments ---
# Usage 1 (GPU/Accelerator): $0 <reservation name> <project-id> <zone> <vm type> <accelerator> <vm count>
# Usage 2 (CPU-only):        $0 <reservation name> <project-id> <zone> <vm type> [none/""/cpu] <vm count>
#
# $1: Reservation Name (e.g., "my-reservation" or "test-cpu-res")
# $2: Google Cloud Project ID
# $3: Zone (e.g., "us-central1-a")
# $4: VM Type (e.g., "g2-standard-8" or "n1-standard-16")
# $5: Accelerator config (e.g., "type=nvidia-l4,count=1") or "none"/omitted for CPU reservations
# $6: Desired VM Count (e.g., 10) [or $5 if accelerator argument is omitted]

# --- Basic Script Setup and Validation ---
if [[ "$#" -lt 5 ]] || [[ "$#" -gt 6 ]]; then
    echo "Usage (CPU or GPU without explicit accelerator): $0 <reservation name> <project-id> <zone> <vm type> <vm count>"
    echo "Usage (GPU with accelerator):                    $0 <reservation name> <project-id> <zone> <vm type> <accelerator config|none> <vm count>"
    echo ""
    echo "Optional Environment Variables:"
    echo "  RESERVATION_CHILD_PROJECTS : Comma-separated child project IDs to share reservation with."
    echo "  LOCAL_SSD (or LSSD)        : Local SSD configuration (e.g., \"interface=nvme,size=375,count=2\")."
    echo "  RETRY_RATE                 : Seconds to wait between retry attempts (default: 60)."
    echo "  INCREMENT                  : Number of VMs to add per upsize attempt (default: 1)."
    echo "  MAX_ATTEMPTS               : Maximum failed retry attempts (default: 0 / infinite)."
    echo ""
    echo "Example (GPU): $0 my-gpu-res my-proj-id us-central1-a g2-standard-8 \"type=nvidia-l4,count=1\" 10"
    echo "Example (CPU + LSSD): LOCAL_SSD=\"interface=scsi,size=375,count=1\" $0 my-cpu-res my-proj-id us-central1-a n1-standard-16 2"
    echo "Example (Shared GPU): RESERVATION_CHILD_PROJECTS=\"proj-1,proj-2\" $0 my-shared-res my-proj-id us-central1-a g2-standard-8 \"type=nvidia-l4,count=1\" 5"
    exit 1
fi

set -o pipefail # Ensures commands in a pipeline fail correctly

NAME="$1"
PROJECT="$2"
ZONE="$3"
VM_TYPE="$4"

if [[ "$#" -eq 5 ]]; then
    ACCELERATOR="none"
    VM_COUNT="$5"
else
    ACCELERATOR="$5"
    VM_COUNT="$6"
fi

# --- Optional Feature Configurations (Configurable via Environment Variables or set directly here) ---
# To create a shared reservation, specify child project IDs comma-separated (excluding hosting project):
# e.g., RESERVATION_CHILD_PROJECTS="child-project-1,child-project-2"
RESERVATION_CHILD_PROJECTS=${RESERVATION_CHILD_PROJECTS:-""}

# To reserve Local SSDs (LSSD) with the instances, specify the local-ssd configuration string:
# e.g., LOCAL_SSD="interface=nvme,size=375,count=2"
LOCAL_SSD=${LOCAL_SSD:-${LSSD:-""}}

# --- Retry Strategy Configuration ---
RETRY_RATE=${RETRY_RATE:-60}     # Seconds to wait between attempts
INCREMENT=${INCREMENT:-1}       # How many VMs to add per attempt
MAX_ATTEMPTS=${MAX_ATTEMPTS:-0} # Maximum failed attempts before exiting (0 for infinite loop)

# --- Normalize Optional Flags (Accelerators, Sharing, and Local SSD) ---
ACCEL_FLAG=()
ACCEL_DESC="none (CPU-only or integrated)"
ACCEL_LOWER=$(echo "$ACCELERATOR" | tr '[:upper:]' '[:lower:]')
if [[ -n "$ACCELERATOR" ]] && [[ "$ACCEL_LOWER" != "none" ]] && [[ "$ACCEL_LOWER" != "cpu" ]] && [[ "$ACCEL_LOWER" != "null" ]]; then
    ACCEL_FLAG=("--accelerator=$ACCELERATOR")
    ACCEL_DESC="$ACCELERATOR"
fi

SHARE_FLAGS=()
SHARE_DESC="Local (unshared)"
if [[ -n "$RESERVATION_CHILD_PROJECTS" ]]; then
    SHARE_FLAGS=("--share-setting=projects" "--share-with=$RESERVATION_CHILD_PROJECTS")
    SHARE_DESC="Shared with: $RESERVATION_CHILD_PROJECTS"
fi

LSSD_FLAG=()
LSSD_DESC="none"
if [[ -n "$LOCAL_SSD" ]]; then
    LSSD_FLAG=("--local-ssd=$LOCAL_SSD")
    LSSD_DESC="$LOCAL_SSD"
fi

echo "--> Goal: Ensure reservation '$NAME' in '$ZONE' has $VM_COUNT instances of type: $VM_TYPE"
echo "    Accelerator: $ACCEL_DESC"
echo "    Sharing:     $SHARE_DESC"
echo "    Local SSD:   $LSSD_DESC"

# --- Main Loop ---
ATTEMPT=0
while true; do
    # Get the current status of the reservation
    CURRENT_COUNT=$(gcloud beta compute reservations describe "$NAME" --project="$PROJECT" --zone="$ZONE" --format 'get(specificReservation.assured_count)' 2>/dev/null)
    GCLOUD_STATUS=$?

    # --- Scenario 1: Reservation DOES NOT Exist ---
    if [[ $GCLOUD_STATUS -ne 0 ]]; then
        echo "Reservation '$NAME' does not exist. Attempting to create it with 1 instance..."
        # Try to create the reservation with a single VM to start
        gcloud beta compute reservations create "$NAME" \
            --project="$PROJECT" \
            --zone="$ZONE" \
            --machine-type="$VM_TYPE" \
            "${ACCEL_FLAG[@]}" \
            "${SHARE_FLAGS[@]}" \
            "${LSSD_FLAG[@]}" \
            --vm-count=1
        
        if [[ $? -eq 0 ]]; then
            echo "--> Successfully created initial reservation."
            # Reset attempt counter on success and continue to the next loop iteration
            ATTEMPT=0
            continue
        else
            echo "--> Failed to create reservation. Will retry."
        fi

    # --- Scenario 2: Reservation Exists but is SMALLER than desired ---
    elif [[ "$CURRENT_COUNT" -lt "$VM_COUNT" ]]; then
        echo "Reservation exists with $CURRENT_COUNT VMs. Goal is $VM_COUNT. Attempting to upsize..."
        NEW_COUNT=$((CURRENT_COUNT + INCREMENT))

        gcloud beta compute reservations update "$NAME" \
            --project="$PROJECT" \
            --zone="$ZONE" \
            --vm-count="$NEW_COUNT" &>/dev/null
        
        if [[ $? -eq 0 ]]; then
            echo "--> Successfully upsized reservation to $NEW_COUNT."
            # Reset attempt counter on success
            ATTEMPT=0
        else
            echo "--> Failed to upsize reservation. Will retry."
        fi

    # --- Scenario 3: Reservation Exists and MEETS or EXCEEDS the goal ---
    else
        echo "✅ Success! Desired reservation count of $VM_COUNT has been met or exceeded. Current count: $CURRENT_COUNT."
        exit 0
    fi
    
    # Check attempt threshold before waiting for retry
    ATTEMPT=$((ATTEMPT + 1))
    if [[ "$MAX_ATTEMPTS" -gt 0 ]] && [[ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]]; then
        echo "--> Maximum failed attempts ($MAX_ATTEMPTS) reached without meeting the target count. Exiting."
        exit 2
    fi

    echo "Retrying in $RETRY_RATE seconds..."
    sleep $RETRY_RATE
done
