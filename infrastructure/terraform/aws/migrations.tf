# Preserve the existing Terraform state addresses when the bootstrap-only
# EBS resources become conditional for Golden-AMI mode.
moved {
  from = aws_ebs_volume.lab_data
  to   = aws_ebs_volume.lab_data[0]
}

moved {
  from = aws_ebs_volume.cinder
  to   = aws_ebs_volume.cinder[0]
}

moved {
  from = aws_volume_attachment.lab_data
  to   = aws_volume_attachment.lab_data[0]
}

moved {
  from = aws_volume_attachment.cinder
  to   = aws_volume_attachment.cinder[0]
}
