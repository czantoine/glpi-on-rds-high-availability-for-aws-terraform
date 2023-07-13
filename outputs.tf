# Authored by Antoine CICHOWICZ | Github: Yris Ops
# Copyright: Apache License 2.0

output "GLPIEnpoint" {
  description = "GLPI MariaDB Endpoint"
  value       = aws_db_instance.RDSInstance.endpoint
}
