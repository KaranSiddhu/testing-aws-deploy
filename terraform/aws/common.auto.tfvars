# Values shared by every layer.
#
# The .auto.tfvars suffix means Terraform loads this automatically, with no
# -var-file flag. Symlinked into each layer, so this file is the single place
# these change.
#
# EDIT THIS FILE, never the symlink inside a layer - they are the same file, and
# editing through a symlink is fine, but doing it deliberately here keeps it
# obvious that the change affects every layer.

region  = "us-east-1"
project = "dummy-hello"
