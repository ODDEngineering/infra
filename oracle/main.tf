terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "5.36.0"
    }
  }
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  private_key  = var.private_key
  fingerprint  = var.fingerprint
  region       = var.region
}

module "vcn" {
  source  = "oracle-terraform-modules/vcn/oci"
  version = "3.6.0"

  vcn_name      = "k8s-vcn"
  vcn_dns_label = "k8svcn"

  compartment_id = var.compartment_id
  region         = var.region

  create_internet_gateway = true
  create_nat_gateway      = true
  create_service_gateway  = true
}

resource "oci_core_security_list" "private_subnet_sl" {
  display_name   = "k8s-private-subnet-sl"
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    source   = "10.0.0.0/16"
    protocol = "all"
  }
}

resource "oci_core_security_list" "public_subnet_sl" {
  display_name   = "k8s-public-subnet-sl"
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id

  egress_security_rules {
    stateless        = false
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  ingress_security_rules {
    stateless   = false
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    protocol    = "all"
  }
  ingress_security_rules {
    stateless   = false
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    tcp_options {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_subnet" "vcn_private_subnet" {
  display_name   = "k8s-private-subnet"
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id

  cidr_block                 = "10.0.1.0/24"
  route_table_id             = module.vcn.nat_route_id
  security_list_ids          = [oci_core_security_list.private_subnet_sl.id]
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_subnet" "vcn_public_subnet" {
  display_name   = "k8s-public-subnet"
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id

  cidr_block        = "10.0.0.0/24"
  route_table_id    = module.vcn.ig_route_id
  security_list_ids = [oci_core_security_list.public_subnet_sl.id]
}

resource "oci_containerengine_cluster" "k8s_cluster" {
  name           = "k8s-cluster"
  compartment_id = var.compartment_id
  vcn_id         = module.vcn.vcn_id

  kubernetes_version = "v1.29.1"
  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.vcn_public_subnet.id
  }
  options {
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
    service_lb_subnet_ids = [oci_core_subnet.vcn_public_subnet.id]
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

resource "oci_containerengine_node_pool" "k8s_node_pool" {
  name           = "k8s-node-pool"
  compartment_id = var.compartment_id
  cluster_id     = oci_containerengine_cluster.k8s_cluster.id

  kubernetes_version = "v1.29.1"
  node_config_details {
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = oci_core_subnet.vcn_private_subnet.id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[1].name
      subnet_id           = oci_core_subnet.vcn_private_subnet.id
    }
    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[2].name
      subnet_id           = oci_core_subnet.vcn_private_subnet.id
    }
    size = 2
  }
  node_shape = "VM.Standard.A1.Flex"
  node_shape_config {
    memory_in_gbs = 12
    ocpus         = 2
  }
  node_source_details {
    # Oracle-Linux-8.9-aarch64-2024.01.26-0-OKE-1.29.1-679
    # us-ashburn-1
    image_id    = "ocid1.image.oc1.iad.aaaaaaaal4ozph2wkorbutsrstg744f3xa6tccuiuug5oprrmk34onvbafaa"
    source_type = "image"
  }
  initial_node_labels {
    key   = "name"
    value = "k8s-cluster"
  }
}
