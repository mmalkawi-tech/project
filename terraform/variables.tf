variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Disaster Recovery AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (prod, staging)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project identifier used in resource names"
  type        = string
  default     = "tc-dr"
}

variable "primary_vpc_cidr" {
  description = "CIDR block for primary VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dr_vpc_cidr" {
  description = "CIDR block for DR VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "db_name" {
  description = "RDS database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "app_instance_type" {
  description = "EC2 instance type for application servers"
  type        = string
  default     = "t3.medium"
}

variable "asg_min_size" {
  description = "Minimum number of EC2 instances in ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of EC2 instances in ASG"
  type        = number
  default     = 6
}

variable "asg_desired_capacity" {
  description = "Desired number of EC2 instances in ASG"
  type        = number
  default     = 2
}

variable "dr_asg_min_size" {
  description = "Minimum instances in DR ASG (kept warm but low cost)"
  type        = number
  default     = 1
}

variable "rpo_hours" {
  description = "Recovery Point Objective in hours"
  type        = number
  default     = 1
}

variable "rto_minutes" {
  description = "Recovery Time Objective in minutes"
  type        = number
  default     = 30
}

variable "alert_email" {
  description = "Email address for DR alerts and notifications"
  type        = string
  default     = "moath.malkawi@techconsulting.tech"
}
