variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "agentcore-bootstrapper"
}

variable "bedrock_model_id" {
  description = "Bedrock model ID for the agent (without regional prefix -- us/eu/apac is added automatically)"
  type        = string
  default     = "anthropic.claude-sonnet-4-5-20250929-v1:0"
}

variable "python_runtime" {
  description = "Python runtime version for AgentCore"
  type        = string
  default     = "PYTHON_3_12"

  validation {
    condition     = contains(["PYTHON_3_10", "PYTHON_3_11", "PYTHON_3_12", "PYTHON_3_13"], var.python_runtime)
    error_message = "Must be PYTHON_3_10, PYTHON_3_11, PYTHON_3_12, or PYTHON_3_13."
  }
}

variable "log_level" {
  description = "Application log level"
  type        = string
  default     = "INFO"
}

variable "memory_event_expiry_days" {
  description = "Days before memory events expire (min 7, max 365)"
  type        = number
  default     = 7

  validation {
    condition     = var.memory_event_expiry_days >= 7 && var.memory_event_expiry_days <= 365
    error_message = "Must be between 7 and 365."
  }
}
