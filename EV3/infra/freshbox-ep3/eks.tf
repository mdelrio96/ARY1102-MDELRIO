# ---------- Amazon EKS: plano de control administrado en las subredes App ----------
# Todo este archivo depende de create_eks (por defecto true). Con false se crea
# solo la base (red, SG, ECR y RDS) y el cluster se agrega despues con otro
# apply; volver a false lo elimina sin tocar la base ni los datos de RDS.

resource "aws_eks_cluster" "main" {
  count = local.eks_count

  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = local.eks_cluster_role_arn

  # vpc-cni, kube-proxy y CoreDNS se instalan abajo como add-ons administrados
  # (versionados y visibles en la consola) en vez de la copia autogestionada.
  bootstrap_self_managed_addons = false

  # API publica con autenticacion IAM (kubectl desde el PC y desde GitHub
  # Actions) y privada para los nodos, que la usan sin salir de la VPC.
  vpc_config {
    subnet_ids              = aws_subnet.app[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_public_access_cidrs
  }

  # Quien crea el cluster (el rol voclabs del lab, el mismo en el PC y en la
  # pipeline) queda como administrador.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # EKS Auto Mode se habilita solo por su controlador de balanceo: el Ingress
  # crea el ALB sin instalar el AWS Load Balancer Controller, que pide un rol IAM
  # propio (IRSA) y el lab no deja crearlo. AWS exige activar los tres bloques
  # juntos; node_pools vacio = Auto Mode no lanza nodos propios, el computo es
  # el Managed Node Group de abajo.
  compute_config {
    enabled    = true
    node_pools = []
  }

  kubernetes_network_config {
    elastic_load_balancing {
      enabled = true
    }
  }

  storage_config {
    block_storage {
      enabled = true
    }
  }

  upgrade_policy {
    support_type = "STANDARD" # sin cargo de soporte extendido
  }

  tags = { Name = local.cluster_name, Layer = "app" }

  lifecycle {
    precondition {
      condition     = length(data.aws_iam_roles.eks_cluster.arns) == 1 && length(data.aws_iam_roles.eks_nodes.arns) == 1
      error_message = "Se esperaba exactamente un rol LabEksClusterRole y uno LabEksNodeRole en la cuenta del lab (aws iam list-roles)."
    }
  }
}

# ---------- Add-ons de red: antes de los nodos (sin CNI los nodos quedan NotReady) ----------

# Prefix delegation: cada ranura de IP de las ENI recibe un prefijo /28 (16 IP)
# en vez de una IP suelta. Al crear el node group EKS lo detecta y fija maxPods
# en 110 (tope para menos de 30 vCPU) en vez de 11; desde ahi el limite real es
# la CPU y la memoria de cada nodo. Requiere Nitro (t4g lo es) y bloques /28
# libres: las subredes App /25 tienen 8, casi vacias antes de crear el cluster.
resource "aws_eks_addon" "vpc_cni" {
  count = local.eks_count

  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })
}

resource "aws_eks_addon" "kube_proxy" {
  count = local.eks_count

  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# ---------- Nodos: Managed Node Group t4g.small (Graviton) en las 2 subredes App ----------
# El launch template solo agrega lo que el node group no expone: disco gp3
# cifrado, IMDSv2, SG-EKS y la reserva de recursos del kubelet. La AMI la elige
# EKS segun ami_type (no se fija aqui).

resource "aws_launch_template" "eks_nodes" {
  count = local.eks_count

  name                   = "${local.name}-lt-eks-nodes"
  update_default_version = true

  # Con SG propios en el launch template EKS ya no agrega el del cluster: se
  # incluye explicito para conservar el trafico nodo <-> plano de control.
  vpc_security_group_ids = [
    aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id,
    aws_security_group.eks.id,
  ]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = var.node_disk_size
      encrypted             = true # clave administrada aws/ebs (KMS)
      delete_on_termination = true
    }
  }

  # IMDSv2 obligatorio. Dos saltos para que los pods (agente de CloudWatch) lleguen
  # a las credenciales del rol del nodo.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # NodeConfig de AL2023 (nodeadm). EKS agrega el suyo con los datos del cluster
  # y maxPods (ese valor manda en un node group sin AMI propia, asi que aqui no se
  # fija). Este solo da la reserva del kubelet: nodeadm la calcula para los 11
  # pods sin prefijos; con la formula de AWS (255Mi + 11Mi por pod) se reserva
  # para node_pods_reserva, los pods que caben de verdad por CPU.
  user_data = base64encode(<<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="//"

    --//
    Content-Type: application/node.eks.aws

    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      kubelet:
        config:
          kubeReserved:
            cpu: 70m
            memory: ${255 + 11 * var.node_pods_reserva}Mi
            ephemeral-storage: 1Gi
    --//--
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-eks-node", Layer = "app" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${local.name}-ebs-eks-node", Layer = "app" }
  }

  tags = { Name = "${local.name}-lt-eks-nodes" }
}

resource "aws_eks_node_group" "main" {
  count = local.eks_count

  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${local.name}-ng"
  node_role_arn   = local.eks_node_role_arn
  subnet_ids      = aws_subnet.app[*].id
  ami_type        = var.node_ami_type
  instance_types  = [var.node_instance_type]
  capacity_type   = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.eks_nodes[0].id
    version = aws_launch_template.eks_nodes[0].latest_version
  }

  # El node group es un Auto Scaling Group de EC2 repartido entre 1a y 1b.
  scaling_config {
    min_size     = var.node_min_size
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1 # reemplazo de a un nodo (los PDB dejan una replica de cada servicio)
  }

  labels = { project = local.name, layer = "app" }

  tags = { Name = "${local.name}-ng", Layer = "app" }

  # El deseado se puede cambiar en la consola o con eksctl/aws cli durante la
  # demostracion (2 a 4) sin que el siguiente apply lo devuelva.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_route_table_association.app, # salida por el NAT para descargar imagenes
  ]
}

# ---------- Add-ons que corren como pods: despues de los nodos ----------

resource "aws_eks_addon" "coredns" {
  count = local.eks_count

  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

# Fuente de las metricas de CPU que usa el HPA (kubectl top).
resource "aws_eks_addon" "metrics_server" {
  count = local.eks_count

  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

# CloudWatch Container Insights: agente de CloudWatch y Fluent Bit en cada nodo.
# Sin Pod Identity (el lab no deja crear roles) usa el rol del nodo; si a
# LabEksNodeRole le falta CloudWatchAgentServerPolicy, los pods corren pero no
# publican (ver EV2/README.md).
resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.create_eks && var.enable_container_insights ? 1 : 0

  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main, aws_eks_addon.coredns]
}
