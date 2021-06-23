module "k3s" {
  source = "./../.."

  depends_on_    = hcloud_server.agents
  k3s_version    = "latest"
  cluster_domain = "cluster.local"
  cidr = {
    pods     = "10.42.0.0/16"
    services = "10.43.0.0/16"
  }
  drain_timeout  = "30s"
  managed_fields = ["label", "taint"] // ignore annotations

  global_flags = [
    "--flannel-iface ens10",
    "--kubelet-arg cloud-provider=external" // required to use https://github.com/hetznercloud/hcloud-cloud-controller-manager
  ]

  servers = {
    for i in range(length(hcloud_server.control_planes)) :
    hcloud_server.control_planes[i].name => {
      ip = hcloud_server_network.control_planes[i].ip
      connection = {
        host = hcloud_server.control_planes[i].ipv4_address
      }
      flags       = ["--disable-cloud-controller"]
      annotations = { "server_id" : i } // theses annotations will not be managed by this module
    }
  }

  agents = {
    for i in range(length(hcloud_server.agents)) :
    "${hcloud_server.agents[i].name}_node" => {
      name = hcloud_server.agents[i].name
      ip   = hcloud_server_network.agents_network[i].ip
      connection = {
        host = hcloud_server.agents[i].ipv4_address
      }

      labels = { "node.kubernetes.io/pool" = hcloud_server.agents[i].labels.nodepool }
      taints = { "dedicated" : hcloud_server.agents[i].labels.nodepool == "gpu" ? "gpu:NoSchedule" : null }
    }
  }
}

provider "kubernetes" {
  host                   = module.k3s.kubernetes.api_endpoint
  cluster_ca_certificate = module.k3s.kubernetes.cluster_ca_certificate
  client_certificate     = module.k3s.kubernetes.client_certificate
  client_key             = module.k3s.kubernetes.client_key
}

resource "kubernetes_service_account" "bootstrap" {
  depends_on = [module.k3s.kubernetes_ready]

  metadata {
    name      = "bootstrap"
    namespace = "default"
  }
}

resource "kubernetes_cluster_role_binding" "boostrap" {
  depends_on = [module.k3s.kubernetes_ready]

  metadata {
    name = "bootstrap"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "bootstrap"
    namespace = "default"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }
}

data "kubernetes_secret" "sa_credentials" {
  metadata {
    name      = kubernetes_service_account.bootstrap.default_secret_name
    namespace = "default"
  }
}
