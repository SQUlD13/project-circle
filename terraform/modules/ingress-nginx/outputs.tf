output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.ingress_nginx.name
}

output "namespace" {
  description = "Namespace where Ingress NGINX is deployed"
  value       = helm_release.ingress_nginx.namespace
}
