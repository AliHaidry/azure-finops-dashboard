variable "resource_group_name"  { type = string }
variable "location"             { type = string }
variable "environment"          { type = string }
variable "sku_name"             { type = string }
variable "key_vault_uri"        { type = string }
variable "pg_connection_string" {
  type      = string
  sensitive = true
}
variable "key_vault_id"         { type = string }
variable "tags"                 { type = map(string) }
