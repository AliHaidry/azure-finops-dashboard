variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "environment"         { type = string }
variable "admin_username"      { type = string }
variable "sku_name"            { type = string }
variable "storage_mb"          { type = number }
variable "pg_version"          { type = string }
variable "tags"                { type = map(string) }
