# Preserve existing runtime state when bootstrap resources become conditional.
# A cluster created before bootstrap retirement support must not recreate its
# bootstrap VM merely because count was added to these resources.

moved {
  from = openstack_networking_port_v2.bootstrap
  to   = openstack_networking_port_v2.bootstrap[0]
}

moved {
  from = openstack_compute_instance_v2.bootstrap
  to   = openstack_compute_instance_v2.bootstrap[0]
}
