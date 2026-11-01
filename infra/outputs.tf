output "name_suffix" {
  value = random_string.suffix.result
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "function_app_name" {
  value = azurerm_function_app_flex_consumption.this.name
}

output "products_url" {
  value = "https://${azurerm_function_app_flex_consumption.this.default_hostname}/api/products"
}

output "master_key" {
  description = "Host master key; send as x-functions-key when calling upsertProduct."
  value       = data.azurerm_function_app_host_keys.this.primary_key
  sensitive   = true
}

output "default_function_key" {
  description = "Default function key (narrower than the master key)."
  value       = data.azurerm_function_app_host_keys.this.default_function_key
  sensitive   = true
}
