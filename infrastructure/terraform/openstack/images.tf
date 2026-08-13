resource "openstack_images_image_v2" "ubuntu_2404" {
  name             = var.ubuntu_image_name
  image_source_url = var.ubuntu_image_source_url
  container_format = "bare"
  disk_format      = "qcow2"
  visibility       = "private"

  min_disk_gb = 10
  min_ram_mb  = 1024

  tags = [
    "base-image",
    "ubuntu",
    "24.04",
    "amd64",
  ]
}
