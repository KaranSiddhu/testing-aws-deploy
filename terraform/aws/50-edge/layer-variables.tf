variable "app_host" {
  description = "Public hostname for the frontend."
  type        = string
}

variable "api_host" {
  description = "Public hostname for the backend. A second door for /docs and curl; the app itself still calls /api on the frontend's own origin."
  type        = string
}
