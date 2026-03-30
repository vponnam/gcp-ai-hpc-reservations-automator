#!/bin/bash
# Retrying Reservations Script - Corrected Version
#
# Creates a reservation if it doesn't exist, then incrementally
# increases its size until the desired count is met. It retries
# on failure.
# orgPolicy for shared allowing reservations: https://docs.cloud.google.com/compute/docs/instances/manage-shared-reservations-creation#allow-restrict-projects

# --- Command-line Arguments ---
# $1: Reservation Name (e.g., "my-reservation")
# $2: Google Cloud Project ID
# $3: Zone (e.g., "us-central1-a")
# $4: VM Type and options, in quotes (e.g., "g2-standard-8 --accelerator=type=nvidia-l4,count=1")
# $5: Desired VM Count (e.g., 10)

# --- Basic Script Setup and Validation ---
if [[ "$#" -ne 6 ]]; then
    echo "Usage: $0 <reservation name> <project-id> <zone> \"<vm type with options>\" <vm count>"
    echo "Example: $0 my-res-name my-proj-id us-central1-a \"n2-standard-8 --accelerator=count=1,type=nvidia-tesla-t4\" 10"
    exit 1
fi

set -o pipefail # Ensures commands in a pipeline fail correctly

NAME="$1"
PROJECT="$2"
ZONE="$3"
VM_TYPE="$4"
ACCELERATOR="$5"
VM_COUNT="$6"
# DELETE_DATE="$7"
RESERVATION_CHILD_PROJECTS="projectID1,projectID2" #Exclude the hosting project from the list

# --- Configuration ---
RETRY_RATE=60   # Seconds to wait between attempts
INCREMENT=1     # How many VMs to add per attempt

echo "--> Goal: Ensure reservation '$NAME' in '$ZONE' has $VM_COUNT instances of type: $VM_TYPE"

# --- Main Loop ---
while true; do
    # Get the current status of the reservation
    CURRENT_COUNT=$(gcloud beta compute reservations describe "$NAME" --project="$PROJECT" --zone="$ZONE" --format 'get(specificReservation.assured_count)' 2>/dev/null)
    GCLOUD_STATUS=$?

    # --- Scenario 1: Reservation DOES NOT Exist ---
    if [[ $GCLOUD_STATUS -ne 0 ]]; then
        echo "Reservation '$NAME' does not exist. Attempting to create it with 1 instance..."
        # Try to create the reservation with a single VM to start
        gcloud beta compute reservations create "$NAME" \
            --share-setting="projects" \
            --share-with="$RESERVATION_CHILD_PROJECTS" \
            --project="$PROJECT" \
            --zone="$ZONE" \
            --machine-type="$VM_TYPE" \
            --accelerator="$ACCELERATOR" \
            --vm-count=1
        
        if [[ $? -eq 0 ]]; then
            echo "--> Successfully created initial reservation."
            # Continue to the next loop iteration to begin upsizing
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
            # If we just hit our target, we'll confirm and exit in the next loop iteration
        else
            echo "--> Failed to upsize reservation. Will retry."
        fi

    # --- Scenario 3: Reservation Exists and MEETS or EXCEEDS the goal ---
    else
        echo "✅ Success! Desired reservation count of $VM_COUNT has been met or exceeded. Current count: $CURRENT_COUNT."
        exit 0
    fi
    
    # Wait before the next attempt
    echo "Retrying in $RETRY_RATE seconds..."
    sleep $RETRY_RATE
done
