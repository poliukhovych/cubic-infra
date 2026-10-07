variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  description = "GHCR images are amd64-only, so stick to x86 instance families."
  type        = string
  default     = "t3.small"
}

variable "env_file" {
  description = "Path to the production .env that will be written to the server."
  type        = string
}

variable "domain" {
  description = "Domain with an A record pointing at the Elastic IP. Empty = plain HTTP on the IP."
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "Public key for SSH access as 'ubuntu'. Empty = SSH port stays closed."
  type        = string
  default     = ""
}

variable "ssh_allowed_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "infra_repo" {
  type    = string
  default = "https://github.com/poliukhovych/cubic-infra.git"
}

variable "infra_ref" {
  type    = string
  default = "main"
}
