# resource "aws_eks_cluster" "dev_eks_cluster" {
#   name     = "${var.environment}-eks-cluster"
#   role_arn = aws_iam_role.eks_cluster_role.arn

#   vpc_config {
#     subnet_ids = module.vpc.private_subnet_ids
#     security_group_ids = [aws_security_group.eks_cluster_sg.id]
#   }

#   depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
  
# }

# resource "aws_eks_node_group" "dev_node_group" {
#   cluster_name    = aws_eks_cluster.dev_eks_cluster.name
#   node_group_name = "${var.environment}-node-group"
#   node_role_arn   = aws_iam_role.eks_node_role.arn
#   subnet_ids      = module.vpc.private_subnet_ids

#   scaling_config {
#     desired_size = var.node_group_desired_size
#     max_size     = var.node_group_max_size
#     min_size     = var.node_group_min_size
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.eks_worker_node_policy,
#     aws_iam_role_policy_attachment.eks_cni_policy,
#     aws_iam_role_policy_attachment.eks_ecr_readonly
#   ]
# }

# resource "aws_security_group" "eks_cluster_sg" {
#   name        = "${var.environment}-eks-cluster-sg"
#   description = "EKS Cluster Security Group"
#   vpc_id      = module.vpc.vpc_id
#     tags = merge(
#         local.common_tags,
#         {
#         Name = "${local.name_prefix}-eks-cluster-sg"
#         }
#     )   
#   ingress {
#     from_port   = 443
#     to_port     = 443
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0/0"]
#   }
# }

data "aws_key_pair" "existing_key" {
  key_name = "practice-key"  # Replace with your key name (must match exactly)
}

resource "aws_eks_cluster" "main_eks" {
    name = "${local.name_prefix}-eks-cluster"
    role_arn = data.aws_iam_role.cluster_role.arn
    # version  = "1.29"
    vpc_config {
      subnet_ids = var.subnet_ids
      endpoint_private_access = true
      endpoint_public_access = true
      security_group_ids = [aws_security_group.eks_SG.id]
    }
    depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy  ]
}



resource "aws_eks_node_group" "main_node_group" {
  cluster_name = aws_eks_cluster.main_eks.name
  node_group_name = "${local.name_prefix}-node-group"
  node_role_arn = data.aws_iam_role.node_role.arn
  subnet_ids = var.subnet_ids
  remote_access {
    ec2_ssh_key = data.aws_key_pair.existing_key.key_name
    source_security_group_ids = [aws_security_group.eks_SG.id]
  }

  scaling_config {
    desired_size = 2
    max_size = 4
    min_size = 1
  }
  ami_type = "AL2023_x86_64_STANDARD"
  instance_types = ["t3.medium"]
  disk_size = 30
  capacity_type = "ON_DEMAND"


  depends_on = [ 
    aws_eks_cluster.main_eks,
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_node_policy,
     ]
  
}

resource "aws_security_group" "eks_SG" {
  name = "${local.name_prefix}-eks-sg"
  description = "EKS_Terraform_SG"
  vpc_id = var.vpc_id
  dynamic "ingress" {
    for_each = var.eks_ingress_rule
    content {
        description = "Inbound Rule"
        from_port = ingress.value.from_port 
        to_port = ingress.value.to_port
        protocol = ingress.value.protocol
        cidr_blocks = [ingress.value.cidr_block]

        }
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.sescurity_group
}


resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name      = aws_eks_cluster.main_eks.name
  addon_name        = "eks-pod-identity-agent"
  depends_on = [aws_eks_cluster.main_eks]
}


resource "aws_eks_addon" "ekf_kube_proxy" {
    cluster_name = aws_eks_cluster.main_eks.name
    addon_name = "kube-proxy"
    depends_on = [ aws_eks_cluster.main_eks ]
}

resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name = aws_eks_cluster.main_eks.name
  namespace    = "kube-system"
  service_account = "aws-node"  # Important: This is the default for vpc-cni
  role_arn     = aws_iam_role.vpc_cni_pod_identity_role.arn
  depends_on = [ 
    aws_eks_cluster.main_eks,
    aws_eks_addon.pod_identity_agent,
    aws_eks_node_group.main_node_group
   ]
}

resource "aws_eks_addon" "eks_vpc_cni" {
    cluster_name = aws_eks_cluster.main_eks.name
    addon_name = "vpc-cni"
    depends_on = [ 
      aws_eks_cluster.main_eks,
      aws_eks_pod_identity_association.vpc_cni
    ]
  
}

resource "aws_eks_addon" "eks_coredns" {
  cluster_name = aws_eks_cluster.main_eks.name
  addon_name   = "coredns"
#   addon_version = "v1.10.1-eksbuild.1"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on   = [
    aws_eks_cluster.main_eks,
    aws_eks_node_group.main_node_group
  ]
}

resource "aws_security_group" "node_group_sg" {
  name        = "${var.environment}-node-group-sg"
  description = "EKS Node Group Security Group"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(
      local.common_tags,
      {
          Name = "${local.name_prefix}-node-group-sg"
      }
  )
  
}




