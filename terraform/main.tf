resource "null_resource" "nixos-remote" {
  provisioner "local-exec" {
    command = "${path.module}/../nixos-remote --store-paths ${var.nixos_partitioner} ${var.nixos_system} ${var.target_user}@${var.target_host} -i ${var.ssh_private_key}"
  }
}
