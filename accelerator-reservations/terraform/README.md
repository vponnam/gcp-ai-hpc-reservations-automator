# GCP Shared Reservation for G4 Instance Family (Terraform)

Terraform configuration for creating **Google Cloud Compute Engine Reservations** using **G4 machine family** (NVIDIA RTX PRO 6000 Blackwell GPUs) as the reference.

## Configuration Details

### Shared Project Logic
The `share_settings` block is conditional. 
- If `shared_project_ids` is empty, the reservation is private to the host project.
- If IDs are added, it automatically configures `SPECIFIC_PROJECTS` sharing.

## Usage
1.  **Define your projects and SSD requirements in `locals`:**

```hcl
locals {
  shared_project_ids = ["project-a", "project-b"] # List of consumer projects
  ssd_count          = 4                          # Must be 0 or 4 for g4-standard-48
}
```

2. Terraform Apply
```bash
terraform init/plan/apply 
```

