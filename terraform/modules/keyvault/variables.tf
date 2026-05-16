variable "resource_group_name"  { type = string }
variable "location"             { type = string }
variable "environment"          { type = string }
variable "tenant_id"            { type = string }
variable "object_id"            { type = string }
variable "pg_connection_string" {
  type      = string
  sensitive = true
}
variable "tags"                 { type = map(string) }
