provider "kubernetes" {
  config_path    = "generated/kubeconfig"
  config_context = "admin@talos"
}

terraform {
  backend "s3" {
    bucket                      = "talos-state"
    key                         = "terraform.tfstate"
    region                      = "ams"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_path_style              = true
    endpoints = {
      s3 = "https://gateway.storjshare.io"
    }
  }
}
