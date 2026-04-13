variable "project_name" { type = string }
variable "environment"  { type = string }
variable "region"       { type = string }

variable "enable_replication" {
  type    = bool
  default = false
}

variable "replication_role_arn" {
  type    = string
  default = null
}

variable "destination_bucket_arn" {
  type    = string
  default = null
}
