################################################################################
# ArgoCD Module - Outputs
################################################################################

output "argocd_namespace" {
  description = "ArgoCD namespace name"
  value       = kubernetes_namespace.argocd.metadata[0].name
}
