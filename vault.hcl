storage "s3" {
  bucket = "BUCKET_NAME"
}
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}
seal "awskms" {
  region = "us-east-1"
  kms_key_id = "KEY_ID"
}
disable_mlock=true
ui=true
