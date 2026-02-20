variable "project_name"    { type = string }
variable "environment"     { type = string }
variable "kms_key_arn"     { type = string }
variable "master_username" { 
    type = string
    default = "admin"
    }
variable "database_name"   { 
    type = string
    default = "oliveyoung"
    }
variable "common_tags"     { type = map(string) }