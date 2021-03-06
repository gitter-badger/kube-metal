# Secure copy etcd TLS assets and kubeconfig to all nodes. Activates kubelet.service
resource "null_resource" "copy_secrets" {
  count = "${var.controller_count + var.worker_count}"

  connection {
    type = "ssh"
    host = "${element(concat(packet_device.controller.*.ipv4_public,
                                    packet_device.worker.*.ipv4_public), count.index)}"

    user        = "core"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    timeout     = "20m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp /etc/hosts /etc/hosts-backup-$(date --utc --iso-8601=seconds)",
      "echo '${data.template_file.hosts.rendered}' | sudo tee /etc/hosts",
    ]
  }

  provisioner "file" {
    content     = "${module.bootkube.kubeconfig}"
    destination = "$HOME/kubeconfig"
  }

  provisioner "file" {
    content     = "${module.bootkube.etcd_ca_cert}"
    destination = "$HOME/etcd-client-ca.crt"
  }

  provisioner "file" {
    content     = "${module.bootkube.etcd_client_cert}"
    destination = "$HOME/etcd-client.crt"
  }

  provisioner "file" {
    content     = "${module.bootkube.etcd_client_key}"
    destination = "$HOME/etcd-client.key"
  }

  provisioner "file" {
    content     = "${module.bootkube.etcd_server_cert}"
    destination = "$HOME/etcd-server.crt"
  }

  provisioner "file" {
    content     = "${module.bootkube.etcd_server_key}"
    destination = "$HOME/etcd-server.key"
  }

  provisioner "file" {
    content     = "${module.bootkube.etcd_peer_cert}"
    destination = "$HOME/etcd-peer.crt"
  }

  provisioner "file" {
    content     = "${module.bootkube.etcd_peer_key}"
    destination = "$HOME/etcd-peer.key"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/ssl/etcd/etcd",
      "sudo mkdir -p /etc/kubernetes",
      "sudo mv etcd-client* /etc/ssl/etcd/",
      "sudo cp /etc/ssl/etcd/etcd-client-ca.crt /etc/ssl/etcd/etcd/server-ca.crt",
      "sudo mv etcd-server.crt /etc/ssl/etcd/etcd/server.crt",
      "sudo mv etcd-server.key /etc/ssl/etcd/etcd/server.key",
      "sudo cp /etc/ssl/etcd/etcd-client-ca.crt /etc/ssl/etcd/etcd/peer-ca.crt",
      "sudo mv etcd-peer.crt /etc/ssl/etcd/etcd/peer.crt",
      "sudo mv etcd-peer.key /etc/ssl/etcd/etcd/peer.key",
      "sudo chown -R etcd:etcd /etc/ssl/etcd",
      "sudo chmod -R 500 /etc/ssl/etcd",
    ]
  }
}

# Secure copy bootkube assets to ONE controller and start bootkube to perform
# one-time self-hosted cluster bootstrapping.
resource "null_resource" "bootkube_start" {
  # Without depends_on, this remote-exec may start before the kubeconfig copy.
  # Terraform only does one task at a time, so it would try to bootstrap
  # Kubernetes and Tectonic while no Kubelets are running. Ensure all nodes
  # receive a kubeconfig before proceeding with bootkube and tectonic.
  depends_on = ["null_resource.copy_secrets"]

  connection {
    type        = "ssh"
    host        = "${packet_device.controller.0.ipv4_public}"
    user        = "core"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    timeout     = "20m"
  }

  provisioner "file" {
    source      = "${var.asset_dir}"
    destination = "$HOME/assets"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /home/core/kubeconfig /etc/kubernetes/kubeconfig",
      "sleep 15",
      "sudo mv /home/core/assets /opt/bootkube",
      "sudo systemctl start bootkube",
    ]
  }
}

# Start kubelet on the rest of the controllers.
resource "null_resource" "cluster_start_controller" {
  count      = "${var.controller_count - 1}"
  depends_on = ["null_resource.bootkube_start"]

  connection {
    type        = "ssh"
    host        = "${element(packet_device.controller.*.ipv4_public, count.index + 1)}"
    user        = "core"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    timeout     = "20m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /home/core/kubeconfig /etc/kubernetes/kubeconfig",
    ]
  }
}

# Start kubelet on the workers.
resource "null_resource" "cluster_start_worker" {
  count      = "${var.worker_count}"
  depends_on = ["null_resource.bootkube_start"]

  connection {
    type        = "ssh"
    host        = "${element(packet_device.worker.*.ipv4_public, count.index)}"
    user        = "core"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    timeout     = "20m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /home/core/kubeconfig /etc/kubernetes/kubeconfig",
    ]
  }
}
