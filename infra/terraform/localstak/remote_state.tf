terraform {
  backend "s3" {
    # Nota: Estos valores se configuran dinámicamente con 'terraform init -backend-config=...'
    # Ver: scripts/init_tfstate.sh
    
    # Valores por defecto (se sobrescriben en init)
    bucket = "la-huella-remote-state"
    key    = "global/terraform.tfstate"
    region = "eu-west-1"

    # Configuración para LocalStack
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}