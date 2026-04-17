locals {
  # Change this to 0 or 4 to satisfy the G4 requirement
  ssd_count = 4

  # Add your Project IDs here. If the list is empty, the reservation remains local to the hosting project.
  # constraints/compute.sharedReservationsOwnerProjects needs to be updated to allow sharing.
  shared_project_ids = [
    # "projectID-1",
    # "projectID-2",
    # "projectID-3"
  ]
}

resource "google_compute_reservation" "g4_infra_reservation" {
  name    = "vponnam-g4-reservation"
  zone    = "us-central1-b" # Verify G4 availability in your target region
  project = "northam-ce-mlai-tpu"

  specific_reservation_required = false #This means reservation auto applies 

  # Outer dynamic block: Only creates share_settings if there are projects in the list
  dynamic "share_settings" {
    for_each = length(local.shared_project_ids) > 0 ? [1] : []
    content {
      share_type = "SPECIFIC_PROJECTS"

      # Inner dynamic block: Iterates through the list to map each project
      dynamic "project_map" {
        for_each = local.shared_project_ids
        content {
          id = project_map.value
        }
      }
    }
  }

  specific_reservation {
    count = 2

    instance_properties {
      machine_type     = "g4-standard-48"
      min_cpu_platform = "Automatic" #Default

      guest_accelerators {
        accelerator_type  = "nvidia-rtx-pro-6000"
        accelerator_count = 1
      }

      # g4-standard-48 requires exactly 4 blocks if using Local SSD
      dynamic "local_ssds" {
        for_each = range(local.ssd_count)
        content {
          disk_size_gb = 375
          interface    = "NVME"
        }
      }
    }
  }
}