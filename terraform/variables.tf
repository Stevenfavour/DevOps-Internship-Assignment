variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "zone" {
  description = "AWS availability zone"
  type        = string
  default     = "eu-north-1a"
}

variable "machine_type" {
  description = "AWS instance type"
  type        = string
  default     = "t3.medium"
}

variable "instance_name" {
  description = "Name of the VM instance"
  type        = string
  default     = "quickstart-vm"
}
