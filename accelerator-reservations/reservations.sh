#!/bin/bash
# Retrying Reservations Script - CPU, GPU, Local SSD & Shared Reservation Support
#
# Creates a compute reservation if it doesn't exist, then incrementally
# increases its size until the desired count is met. It retries
# on failure. Supports both CPU-only and GPU/Accelerator reservations,
# Local SSD (LSSD) attachments, and Shared Reservations across projects.
# orgPolicy for shared allowing reservations: https://docs.cloud.google.com/compute/docs/instances/manage-shared-reservations-creation#allow-restrict-projects

# --- Command-line Arguments ---
# Usage 1 (GPU/TPU/Accelerator): $0 <reservation name> <project-id> <zone> <vm type> <accelerator|tpu|none> <vm count>
# Usage 2 (CPU or Integrated TPU): $0 <reservation name> <project-id> <zone> <vm type> <vm count>
#
# $1: Reservation Name (e.g., "my-reservation" or "vponnam-v6e-res")
# $2: Google Cloud Project ID
# $3: Zone (e.g., "us-central1-a" or "us-east1-d")
# $4: VM Type or TPU Shorthand (e.g., "g2-standard-8", "n1-standard-16", "ct6e-standard-4t", "v6e-4")
# $5: Accelerator config (e.g., "type=nvidia-l4,count=1", "tpu", or "none"/omitted for CPU/TPU reservations)
# $6: Desired VM Count (e.g., 10) [or $5 if accelerator argument is omitted]

# --- Basic Script Setup and Validation ---
if [[ "$#" -lt 5 ]] || [[ "$#" -gt 6 ]]; then
    echo "Usage (CPU or Integrated TPU):  $0 <reservation name> <project-id> <zone> <vm type|tpu type> <vm count>"
    echo "Usage (GPU/TPU with 6 args):    $0 <reservation name> <project-id> <zone> <vm type|tpu type> <accelerator config|tpu|none> <vm count>"
    echo ""
    echo "Optional Environment Variables:"
    echo "  RESERVATION_CHILD_PROJECTS : Comma-separated child project IDs to share reservation with."
    echo "  LOCAL_SSD (or LSSD)        : Local SSD configuration (e.g., \"interface=nvme,size=375,count=2\")."
    echo "  RESOURCE_PREFIX            : Prefix to enforce on resource names and default owner label (e.g., \"vponnam\")."
    echo "  LABELS                     : Comma-separated key=value labels (e.g., \"prefix=vponnam,owner=vponnam,env=test\")."
    echo "  RESOURCE_MANAGER_TAGS      : Comma-separated Resource Manager tags for reservations (e.g., \"tagKeys/123=tagValues/456\")."
    echo "  TPU_CHIPS_PER_VM           : Chips per TPU VM when reserving by chip count (1, 4, or 8; default: 4 for tpu_lite_podslice_v5)."
    echo "  TPU_PROVISION_MODE         : TPU on-demand mode: 'auto' (default), 'reservation', 'gce-vm', or 'queued-resource'."
    echo "  RETRY_RATE                 : Seconds to wait between retry attempts (default: 60)."
    echo "  INCREMENT                  : Number of VMs to add per upsize attempt (default: 1)."
    echo "  MAX_ATTEMPTS               : Maximum failed retry attempts (default: 0 / infinite)."
    echo ""
    echo "Example (GPU): $0 my-gpu-res my-proj-id us-central1-a g2-standard-8 \"type=nvidia-l4,count=1\" 10"
    echo "Example (TPU v5e PodSlice - 24 chips in us-east1-b): RESOURCE_PREFIX=\"vponnam\" $0 vponnam-v5e-res my-proj-id us-east1-b tpu_lite_podslice_v5 tpu 24"
    echo "Example (TPU v6e): RESOURCE_PREFIX=\"vponnam\" $0 vponnam-v6e-res my-proj-id us-east1-d ct6e-standard-4t tpu 1"
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

# Resource prefixing and labeling configuration:
# e.g., RESOURCE_PREFIX="vponnam" and LABELS="prefix=vponnam,owner=vponnam"
RESOURCE_PREFIX=${RESOURCE_PREFIX:-""}
LABELS=${LABELS:-""}
RESOURCE_MANAGER_TAGS=${RESOURCE_MANAGER_TAGS:-""}
TPU_CHIPS_PER_VM=${TPU_CHIPS_PER_VM:-""}

# TPU provisioning mode:
#   auto            : Try GCE On-Demand Reservation first; if the TPU machine family (e.g., ct6e/v6e) is not
#                     supported by GCE On-Demand Reservations API, automatically fall back to on-demand GCE TPU VMs.
#   reservation     : Only attempt GCE On-Demand Reservations (gcloud beta compute reservations create).
#   gce-vm          : Provision on-demand Compute Engine TPU VMs (gcloud compute instances create) with labels.
#   queued-resource : Provision on-demand Cloud TPU Queued Resources (gcloud compute tpus queued-resources create) with labels.
TPU_PROVISION_MODE=${TPU_PROVISION_MODE:-"auto"}

# --- Retry Strategy Configuration ---
RETRY_RATE=${RETRY_RATE:-60}     # Seconds to wait between attempts
INCREMENT=${INCREMENT:-2}       # How many VMs to add per attempt
MAX_ATTEMPTS=${MAX_ATTEMPTS:-0} # Maximum failed attempts before exiting (0 for infinite loop)

# --- Enforce Resource Prefix and Default Labels ---
if [[ -n "$RESOURCE_PREFIX" ]]; then
    if [[ "$NAME" != "${RESOURCE_PREFIX}-"* ]]; then
        NAME="${RESOURCE_PREFIX}-${NAME}"
    fi
    if [[ -z "$LABELS" ]]; then
        LABELS="prefix=${RESOURCE_PREFIX},owner=${RESOURCE_PREFIX}"
    fi
fi

# --- Normalize TPU Shorthands and Detect TPU Machine Families ---
IS_TPU=false
TPU_FAMILY_NAME=""
TPU_ACCEL_TYPE=""
TPU_RUNTIME_VERSION="v2-alpha-tpuv6e"
TPU_IMAGE_FAMILY="ubuntu-accel-2204-amd64-tpu-v5e-v5p-v6e"
TPU_IMAGE_PROJECT="ubuntu-os-accelerator-images"
CHIPS_PER_INSTANCE=0
TOTAL_TPU_CHIPS=0

VM_TYPE_LOWER=$(echo "$VM_TYPE" | tr '[:upper:]' '[:lower:]')
ACCEL_LOWER=$(echo "$ACCELERATOR" | tr '[:upper:]' '[:lower:]')

# Extract optional chip count per VM if passed via accelerator string (e.g., "type=tpu_lite_podslice_v5,count=4")
if [[ -z "$TPU_CHIPS_PER_VM" ]] && [[ "$ACCEL_LOWER" =~ count=([0-9]+) ]]; then
    TPU_CHIPS_PER_VM="${BASH_REMATCH[1]}"
fi

case "$VM_TYPE_LOWER" in
    tpu_lite_podslice_v5|tpu-lite-podslice-v5|ct5lp|v5litepod)
        TPU_FAMILY_NAME="tpu_lite_podslice_v5"
        TPU_RUNTIME_VERSION="v2-alpha-tpuv5-lite"
        IS_TPU=true
        # When tpu_lite_podslice_v5 is specified directly as the target type, interpret VM_COUNT as total chip count
        # (unless TPU_CHIPS_PER_VM=1) and map to ct5lp-hightpu-{1t,4t,8t}
        if [[ -z "$TPU_CHIPS_PER_VM" ]]; then
            if (( VM_COUNT >= 4 && VM_COUNT % 4 == 0 )); then
                TPU_CHIPS_PER_VM=4
            else
                TPU_CHIPS_PER_VM=1
            fi
        fi
        CHIPS_PER_INSTANCE="$TPU_CHIPS_PER_VM"
        TOTAL_TPU_CHIPS="$VM_COUNT"
        VM_COUNT=$(( (TOTAL_TPU_CHIPS + CHIPS_PER_INSTANCE - 1) / CHIPS_PER_INSTANCE ))
        VM_TYPE="ct5lp-hightpu-${CHIPS_PER_INSTANCE}t"
        TPU_ACCEL_TYPE="v5litepod-${CHIPS_PER_INSTANCE}"
        ;;
    tpu_lite_device_v5|tpu-lite-device-v5|ct5l)
        TPU_FAMILY_NAME="tpu_lite_device_v5"
        TPU_RUNTIME_VERSION="v2-alpha-tpuv5-lite"
        IS_TPU=true
        if [[ -z "$TPU_CHIPS_PER_VM" ]]; then
            if (( VM_COUNT >= 4 && VM_COUNT % 4 == 0 )); then
                TPU_CHIPS_PER_VM=4
            else
                TPU_CHIPS_PER_VM=1
            fi
        fi
        CHIPS_PER_INSTANCE="$TPU_CHIPS_PER_VM"
        TOTAL_TPU_CHIPS="$VM_COUNT"
        VM_COUNT=$(( (TOTAL_TPU_CHIPS + CHIPS_PER_INSTANCE - 1) / CHIPS_PER_INSTANCE ))
        VM_TYPE="ct5l-hightpu-${CHIPS_PER_INSTANCE}t"
        TPU_ACCEL_TYPE="v5litepod-${CHIPS_PER_INSTANCE}"
        ;;
    v6e-1|ct6e-standard-1t)
        VM_TYPE="ct6e-standard-1t"
        TPU_FAMILY_NAME="tpus_per_tpu_family (CT6E)"
        TPU_ACCEL_TYPE="v6e-1"
        TPU_RUNTIME_VERSION="v2-alpha-tpuv6e"
        CHIPS_PER_INSTANCE=1
        IS_TPU=true
        ;;
    v6e|v6e-4|ct6e-standard-4t)
        VM_TYPE="ct6e-standard-4t"
        TPU_FAMILY_NAME="tpus_per_tpu_family (CT6E)"
        TPU_ACCEL_TYPE="v6e-4"
        TPU_RUNTIME_VERSION="v2-alpha-tpuv6e"
        CHIPS_PER_INSTANCE=4
        IS_TPU=true
        ;;
    v6e-8|ct6e-standard-8t)
        VM_TYPE="ct6e-standard-8t"
        TPU_FAMILY_NAME="tpus_per_tpu_family (CT6E)"
        TPU_ACCEL_TYPE="v6e-8"
        TPU_RUNTIME_VERSION="v2-alpha-tpuv6e"
        CHIPS_PER_INSTANCE=8
        IS_TPU=true
        ;;
    v5e-1|v5litepod-1|tpu_lite_podslice_v5-1t|ct5lp-hightpu-1t)
        VM_TYPE="ct5lp-hightpu-1t"
        TPU_FAMILY_NAME="tpu_lite_podslice_v5"
        TPU_ACCEL_TYPE="v5litepod-1"
        TPU_RUNTIME_VERSION="v2-alpha-tpuv5-lite"
        CHIPS_PER_INSTANCE=1
        IS_TPU=true
        ;;
    v5e|v5e-4|v5litepod-4|tpu_lite_podslice_v5-4t|ct5lp-hightpu-4t)
        VM_TYPE="ct5lp-hightpu-4t"
        TPU_FAMILY_NAME="tpu_lite_podslice_v5"
        TPU_ACCEL_TYPE="v5litepod-4"
        TPU_RUNTIME_VERSION="v2-alpha-tpuv5-lite"
        CHIPS_PER_INSTANCE=4
        IS_TPU=true
        ;;
    v5e-8|v5litepod-8|tpu_lite_podslice_v5-8t|ct5lp-hightpu-8t)
        VM_TYPE="ct5lp-hightpu-8t"
        TPU_FAMILY_NAME="tpu_lite_podslice_v5"
        TPU_ACCEL_TYPE="v5litepod-8"
        TPU_RUNTIME_VERSION="v2-alpha-tpuv5-lite"
        CHIPS_PER_INSTANCE=8
        IS_TPU=true
        ;;
    v5p|v5p-8|ct5p-hightpu-4t)
        VM_TYPE="ct5p-hightpu-4t"
        TPU_FAMILY_NAME="tpu_v5p"
        TPU_ACCEL_TYPE="v5p-8"
        TPU_RUNTIME_VERSION="v2-alpha-tpuv5"
        CHIPS_PER_INSTANCE=4
        IS_TPU=true
        ;;
    v4|v4-8|ct4p-hightpu-4t)
        VM_TYPE="ct4p-hightpu-4t"
        TPU_FAMILY_NAME="tpu_v4"
        TPU_ACCEL_TYPE="v4-8"
        TPU_RUNTIME_VERSION="tpu-vm-tf-2.16.1-pjrt"
        CHIPS_PER_INSTANCE=4
        IS_TPU=true
        ;;
    v3|v3-8|ct3-hightpu-4t)
        VM_TYPE="ct3-hightpu-4t"
        TPU_FAMILY_NAME="tpu_v3"
        TPU_ACCEL_TYPE="v3-8"
        TPU_RUNTIME_VERSION="tpu-vm-base"
        CHIPS_PER_INSTANCE=4
        IS_TPU=true
        ;;
    tpu7x|tpu7x-4|v7x-4|tpu7x-standard-4t)
        VM_TYPE="tpu7x-standard-4t"
        TPU_FAMILY_NAME="tpu7x"
        TPU_ACCEL_TYPE="tpu7x-4"
        TPU_IMAGE_FAMILY="ubuntu-accel-2404-amd64-tpu-tpu7x"
        CHIPS_PER_INSTANCE=4
        IS_TPU=true
        ;;
    ct3*|ct4*|ct5*|ct6*|tpu*)
        IS_TPU=true
        ;;
esac

if [[ "$IS_TPU" == "true" ]] && [[ "$TOTAL_TPU_CHIPS" -eq 0 ]] && [[ "$CHIPS_PER_INSTANCE" -gt 0 ]]; then
    TOTAL_TPU_CHIPS=$(( VM_COUNT * CHIPS_PER_INSTANCE ))
fi

# --- Normalize Optional Flags (Accelerators, Sharing, Local SSD, and Labels) ---
ACCEL_FLAG=()
ACCEL_DESC="none (CPU-only or integrated)"
if [[ "$ACCEL_LOWER" == "tpu" ]] || [[ "$ACCEL_LOWER" == *"tpu_lite_"* ]] || [[ "$ACCEL_LOWER" == *"tpu-lite-"* ]] || [[ "$ACCEL_LOWER" == *"ct5"* ]] || [[ "$ACCEL_LOWER" == *"ct6"* ]] || [[ "$IS_TPU" == "true" && ( "$ACCEL_LOWER" == "none" || -z "$ACCELERATOR" ) ]]; then
    IS_TPU=true
    if [[ "$TOTAL_TPU_CHIPS" -gt 0 ]]; then
        ACCEL_DESC="Integrated Cloud TPU (${TPU_FAMILY_NAME:-$VM_TYPE}: ${CHIPS_PER_INSTANCE} chips/VM, ${TOTAL_TPU_CHIPS} chips total)"
    else
        ACCEL_DESC="Integrated Cloud TPU ($VM_TYPE)"
    fi
elif [[ -n "$ACCELERATOR" ]] && [[ "$ACCEL_LOWER" != "none" ]] && [[ "$ACCEL_LOWER" != "cpu" ]] && [[ "$ACCEL_LOWER" != "null" ]]; then
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

RES_METADATA_FLAGS=()
INSTANCE_LABEL_FLAGS=()
LABELS_DESC="none"
if [[ -n "$LABELS" ]]; then
    # GCE Reservations do not have a --labels flag; record labels in --description and pass --labels to TPU VMs/Nodes.
    RES_METADATA_FLAGS+=("--description=labels:${LABELS}")
    INSTANCE_LABEL_FLAGS+=("--labels=${LABELS}")
    LABELS_DESC="$LABELS"
fi
if [[ -n "$RESOURCE_MANAGER_TAGS" ]]; then
    RES_METADATA_FLAGS+=("--resource-manager-tags=${RESOURCE_MANAGER_TAGS}")
fi

if [[ "$IS_TPU" == "true" ]] && [[ "$TOTAL_TPU_CHIPS" -gt 0 ]]; then
    echo "--> Goal: Ensure reservation '$NAME' in '$ZONE' has $VM_COUNT instances of type: $VM_TYPE (${TOTAL_TPU_CHIPS} ${TPU_FAMILY_NAME:-TPU} chips total)"
else
    echo "--> Goal: Ensure reservation '$NAME' in '$ZONE' has $VM_COUNT instances of type: $VM_TYPE"
fi
echo "    Accelerator: $ACCEL_DESC"
echo "    Sharing:     $SHARE_DESC"
echo "    Local SSD:   $LSSD_DESC"
echo "    Labels:      $LABELS_DESC"
if [[ "$IS_TPU" == "true" ]]; then
    echo "    TPU Mode:    $TPU_PROVISION_MODE"
fi

ACTIVE_MODE="reservation"
if [[ "$IS_TPU" == "true" ]] && [[ "$TPU_PROVISION_MODE" == "gce-vm" || "$TPU_PROVISION_MODE" == "queued-resource" ]]; then
    ACTIVE_MODE="$TPU_PROVISION_MODE"
fi

# --- Helper: Poll & Provision On-Demand GCE TPU VMs when Reservation API does not support the TPU family ---
provision_tpu_gce_vms() {
    local EXISTING_VMS
    EXISTING_VMS=$(gcloud compute instances list \
        --project="$PROJECT" \
        --zones="$ZONE" \
        --filter="name~'^${NAME}-[0-9]+$'" \
        --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$EXISTING_VMS" -ge "$VM_COUNT" ]]; then
        echo "✅ Success! Desired on-demand TPU VM count of $VM_COUNT has been met or exceeded. Current count: $EXISTING_VMS."
        exit 0
    fi

    local NEXT_INDEX=$((EXISTING_VMS + 1))
    local TARGET_TOTAL=$((EXISTING_VMS + INCREMENT))
    if [[ "$EXISTING_VMS" -eq 0 ]]; then
        TARGET_TOTAL=1
    fi
    if [[ "$TARGET_TOTAL" -gt "$VM_COUNT" ]]; then
        TARGET_TOTAL="$VM_COUNT"
    fi

    local EXTRA_TPU_VM_FLAGS=()
    if [[ "$VM_TYPE" == "ct6e-standard-8t" ]]; then
        EXTRA_TPU_VM_FLAGS+=("--threads-per-core=1")
    fi

    local CREATED_ANY=false
    for ((i = NEXT_INDEX; i <= TARGET_TOTAL; i++)); do
        local INSTANCE_NAME="${NAME}-${i}"
        echo "Attempting to create on-demand TPU VM '$INSTANCE_NAME' ($VM_TYPE) in '$ZONE'..."
        gcloud compute instances create "$INSTANCE_NAME" \
            --project="$PROJECT" \
            --zone="$ZONE" \
            --machine-type="$VM_TYPE" \
            --image-family="$TPU_IMAGE_FAMILY" \
            --image-project="$TPU_IMAGE_PROJECT" \
            --maintenance-policy=TERMINATE \
            "${INSTANCE_LABEL_FLAGS[@]}" \
            "${EXTRA_TPU_VM_FLAGS[@]}"
        if [[ $? -eq 0 ]]; then
            echo "--> Successfully created on-demand TPU VM '$INSTANCE_NAME'."
            CREATED_ANY=true
        else
            echo "--> Failed to create on-demand TPU VM '$INSTANCE_NAME'. Will retry."
            break
        fi
    done

    if [[ "$CREATED_ANY" == "true" ]]; then
        return 0
    fi
    return 1
}

# --- Helper: Poll & Provision On-Demand Cloud TPU Queued Resources ---
provision_tpu_queued_resources() {
    local EXISTING_QR
    EXISTING_QR=$(gcloud compute tpus queued-resources list \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --filter="name~'/${NAME}-[0-9]+$' AND state.state=(ACTIVE,CREATING,ACCEPTED,PROVISIONING,WAITING_FOR_RESOURCES)" \
        --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$EXISTING_QR" -ge "$VM_COUNT" ]]; then
        echo "✅ Success! Desired on-demand TPU Queued Resource count of $VM_COUNT has been met or exceeded. Current count: $EXISTING_QR."
        exit 0
    fi

    local NEXT_INDEX=$((EXISTING_QR + 1))
    local QR_NAME="${NAME}-${NEXT_INDEX}"
    local NODE_NAME="${NAME}-node-${NEXT_INDEX}"
    echo "Attempting to create on-demand TPU Queued Resource '$QR_NAME' (accelerator: ${TPU_ACCEL_TYPE:-$VM_TYPE}) in '$ZONE'..."
    gcloud compute tpus queued-resources create "$QR_NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --accelerator-type="${TPU_ACCEL_TYPE:-$VM_TYPE}" \
        --runtime-version="$TPU_RUNTIME_VERSION" \
        --node-id="$NODE_NAME" \
        "${INSTANCE_LABEL_FLAGS[@]}"
    if [[ $? -eq 0 ]]; then
        echo "--> Successfully submitted on-demand TPU Queued Resource '$QR_NAME'."
        return 0
    else
        echo "--> Failed to create on-demand TPU Queued Resource '$QR_NAME'. Will retry."
        return 1
    fi
}

# --- Main Loop ---
ATTEMPT=0
while true; do
    if [[ "$ACTIVE_MODE" == "gce-vm" ]]; then
        if provision_tpu_gce_vms; then
            ATTEMPT=0
            continue
        fi
    elif [[ "$ACTIVE_MODE" == "queued-resource" ]]; then
        if provision_tpu_queued_resources; then
            ATTEMPT=0
            continue
        fi
    else
        # Get the current status of the reservation
        CURRENT_COUNT=$(gcloud beta compute reservations describe "$NAME" --project="$PROJECT" --zone="$ZONE" --format 'get(specificReservation.assured_count)' 2>/dev/null)
        GCLOUD_STATUS=$?

        # --- Scenario 1: Reservation DOES NOT Exist ---
        if [[ $GCLOUD_STATUS -ne 0 ]]; then
            echo "Reservation '$NAME' does not exist. Attempting to create it with 1 instance..."
            # Try to create the reservation with a single VM to start
            CREATE_OUTPUT=$(gcloud beta compute reservations create "$NAME" \
                --project="$PROJECT" \
                --zone="$ZONE" \
                --machine-type="$VM_TYPE" \
                "${ACCEL_FLAG[@]}" \
                "${SHARE_FLAGS[@]}" \
                "${LSSD_FLAG[@]}" \
                "${RES_METADATA_FLAGS[@]}" \
                --vm-count=1 2>&1)
            CREATE_STATUS=$?
            echo "$CREATE_OUTPUT"
            
            if [[ $CREATE_STATUS -eq 0 ]]; then
                echo "--> Successfully created initial reservation."
                # Reset attempt counter on success and continue to the next loop iteration
                ATTEMPT=0
                continue
            elif [[ "$IS_TPU" == "true" ]] && [[ "$TPU_PROVISION_MODE" == "auto" ]] && [[ "$CREATE_OUTPUT" == *"The specified machine family is not supported for on-demand reservations"* ]]; then
                echo "--> Notice: GCP Compute Engine On-Demand Reservations API does not support machine family '$VM_TYPE' (TPU v5e/v5p/v6e/v7x reservations require Calendar Mode Future Reservations or CUDs)."
                echo "--> Switching to On-Demand GCE TPU VM provisioning mode ('gce-vm') for '$NAME' with labels '$LABELS_DESC'..."
                ACTIVE_MODE="gce-vm"
                if provision_tpu_gce_vms; then
                    ATTEMPT=0
                    continue
                fi
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
