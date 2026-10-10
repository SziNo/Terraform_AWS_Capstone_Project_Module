locals {
  # Local path of the private key, matching the ssh-keygen command we used
  ssh_key_path = "~/.ssh/${var.key_pair.name}"

  # Bastion used as the jump host in the generated SSH commands
  jump_bastion_ip = values(module.bastion.public_ips)[0]
}