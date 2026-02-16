resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.8.5"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [
    yamlencode({
      global = {
        domain = var.argocd_domain
      }

      configs = {
        params = {
          "server.insecure" = true
        }
        cm = {
          "timeout.reconciliation"       = "180s"
          "application.instanceLabelKey" = "argocd.argoproj.io/instance"
        }
        ssh = {
          knownHosts = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
        }
      }

      server = {
        service = {
          type = "ClusterIP"
        }
        ingress = {
          enabled          = true
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"      = "ip"
            "alb.ingress.kubernetes.io/group.name"       = var.project_name
            "alb.ingress.kubernetes.io/group.order"      = "1"
            "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
          }
          hosts = [var.argocd_domain]
        }
        metrics = {
          enabled = true
        }
      }

      controller = {
        metrics = {
          enabled = true
        }
      }

      repoServer = {
        metrics = {
          enabled = true
        }
      }

      applicationSet = {
        enabled = true
      }
    })
  ]
}

resource "kubernetes_secret_v1" "argocd_repo" {
  count = var.git_repo_url != "" ? 1 : 0

  metadata {
    name      = "repo-${var.project_name}"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = var.git_repo_url
    sshPrivateKey = var.git_ssh_private_key
  }

  depends_on = [helm_release.argocd]
}
