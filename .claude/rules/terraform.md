---
paths:
  - "terraform/**/*.tf"
  - "terraform/**/*.tfvars"
---

# Terraform Conventions

- Terraform >= 1.10 (S3 native state locking)
- One resource type per file (s3.tf, iam.tf, agentcore.tf, memory.tf, logging.tf)
- All user-configurable values go in `variables.tf` with sensible defaults
- Outputs in `outputs.tf` -- include invoke_command for quick testing
- State backend uses S3 with `use_lockfile = true` (no DynamoDB)
- Run `terraform fmt` before committing
