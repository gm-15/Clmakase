################################################################################
# ArgoCD Module - Main
# CJ Oliveyoung CloudWave Infrastructure
#
# Creates: Namespace + ArgoCD Helm Release
# - GitOps 기반 K8s 배포 자동화
################################################################################

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ------------------------------------------------------------------------------
# ArgoCD Namespace
# ------------------------------------------------------------------------------
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "project"                      = var.project_name
      "environment"                  = var.environment
    }
  }
}

# ------------------------------------------------------------------------------
# ArgoCD Helm Release
# ------------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # ArgoCD Server - LoadBalancer로 외부 접근
  set {
    name  = "server.service.type"
    value = var.server_service_type
  }

  # HA 비활성화 (dev 환경)
  set {
    name  = "redis-ha.enabled"
    value = "false"
  }

  set {
    name  = "controller.replicas"
    value = "1"
  }

  set {
    name  = "server.replicas"
    value = "1"
  }

  set {
    name  = "repoServer.replicas"
    value = "1"
  }

  # Dex (SSO) 비활성화
  set {
    name  = "dex.enabled"
    value = "false"
  }

  # Notifications 비활성화
  set {
    name  = "notifications.enabled"
    value = "false"
  }

  depends_on = [
    kubernetes_namespace.argocd,
  ]
}
