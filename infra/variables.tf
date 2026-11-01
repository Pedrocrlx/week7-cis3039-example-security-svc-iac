variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region (must be one of your permitted locations, e.g. uksouth)."
  type        = string
  default     = "uksouth"
}

variable "node_version" {
  description = "Node.js runtime version for the Function App (Flex Consumption format, e.g. \"22\")."
  type        = string
  default     = "22"
}

variable "instance_memory_in_mb" {
  description = "Flex Consumption instance size: 512, 2048 or 4096. Smaller instances use the free GB-s grant more slowly."
  type        = number
  default     = 512
}

variable "cors_allowed_origins" {
  description = "Origins allowed to call the API cross-domain, e.g. [\"http://localhost:5173\"]."
  type        = list(string)
  default     = []
}

variable "oauth2_jwks_uri" {
  description = "JWKS endpoint, e.g. https://your-tenant.auth0.com/.well-known/jwks.json. Empty disables token validation."
  type        = string
  default     = ""
}

variable "oauth2_issuer" {
  description = "Expected token issuer, e.g. https://your-tenant.auth0.com/."
  type        = string
  default     = ""
}

variable "oauth2_audience" {
  description = "Expected token audience (API identifier), e.g. https://products.shopping.thamco.com."
  type        = string
  default     = ""
}

variable "product_updated_base_url" {
  description = "Base URL of the product-updated receiver. Empty falls back to the dummy console notifier."
  type        = string
  default     = ""
}

variable "product_updated_key" {
  description = "Host key for the product-updated receiver (sent as x-functions-key)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "app_package_path" {
  description = "Optional path to a zip of the built app to deploy. Leave null to publish with `func azure functionapp publish` instead."
  type        = string
  default     = null
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap (GB) for Log Analytics / Application Insights. 0.16 GB/day keeps a month under the 5 GB free allowance; -1 removes the cap."
  type        = number
  default     = 0.16
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
