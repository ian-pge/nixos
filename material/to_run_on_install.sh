sudo tailscale up

sudo virsh net-define /var/lib/libvirt/qemu/networks/default.xml
sudo virsh net-autostart default
sudo virsh net-start    default
