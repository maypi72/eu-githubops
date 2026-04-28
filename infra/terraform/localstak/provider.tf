provider "aws" {
  #Credenciales desde variables de entorno (TF_VAR_aws_access_key, TF_VAR_aws_secret_key)
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region

  # Para facilitar el uso con LocalStack 
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  sts_region                  = var.aws_region
  skip_requesting_account_id  = true

  # Endpoints de LocalStack a través de Ingress
  endpoints {
    s3 = "http://localstack.local"
  }
}