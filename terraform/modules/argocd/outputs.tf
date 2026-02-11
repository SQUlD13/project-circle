output "namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.argocd.name
}
