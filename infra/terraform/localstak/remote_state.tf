terraform {
  backend "s3" {
    bucket = "la-huella-remote-state"
    key    = "global/terraform.tfstate"
    region = "eu-west-1"

    # Endpoint
    endpoints = {
      s3 = "http://localstack.local"
    }
    #variables
      access_key = "test"
      secret_key = "test"
    # Configuraciones necesarias para LocalStack e Ingress

    use_path_style              = true 
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }    
}