variable "project_name"       { type = string }
variable "environment"        { type = string }
variable "vpc_id"             { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "db_name"            { type = string }
variable "instance_class"     { type = string }
variable "is_primary"         { type = bool }

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "source_db_arn" {
  type    = string
  default = null
}
