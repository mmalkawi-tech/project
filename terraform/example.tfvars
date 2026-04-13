# Copy this file to terraform.tfvars and fill in secrets
# terraform.tfvars is gitignored — never commit secrets

primary_region       = "us-east-1"
dr_region            = "us-west-2"
environment          = "prod"
project_name         = "tc-dr"
primary_vpc_cidr     = "10.0.0.0/16"
dr_vpc_cidr          = "10.1.0.0/16"
db_name              = "appdb"
db_username          = "CHANGE_ME"
db_password          = "CHANGE_ME"
db_instance_class    = "db.t3.medium"
app_instance_type    = "t3.medium"
asg_min_size         = 2
asg_max_size         = 6
asg_desired_capacity = 2
dr_asg_min_size      = 1
rpo_hours            = 1
rto_minutes          = 30
alert_email          = "moath.malkawi@techconsulting.tech"
