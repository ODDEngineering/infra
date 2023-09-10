variable "tenancy_ocid" {
  type = string
}

variable "user_ocid" {
  type = string
}

variable "private_key" {
  type = string
  description = "The private SSH key for API Key Auth"
}

variable "fingerprint" {
  type = string
  description = "The SSH Key fingerprint"
}

variable "compartment_id" {
  type        = string
  description = "The compartment to create the resources in"
}

variable "region" {
  type        = string
  description = "The region to provision the resources in"
}
