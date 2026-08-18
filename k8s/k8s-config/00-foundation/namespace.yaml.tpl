# The namespace everything else goes into.
#
# A .tpl even though the only variable is the name, so that standing up a second
# environment is an env.sh change and nothing else.
apiVersion: v1
kind: Namespace
metadata:
  name: ${NS}
  labels:
    app.kubernetes.io/part-of: ${NS}

    # Pod Security Standards. "baseline" blocks the obviously dangerous things
    # (host network, privileged containers) while allowing normal workloads.
    #
    # Worth knowing for later: AWNIC's monitoring namespace has to be
    # "privileged" instead, because node-exporter needs hostNetwork and hostPID
    # and promtail needs hostPath. Under "baseline" the DaemonSet is accepted
    # and NO POD IS EVER CREATED - a silent failure that reads as a working
    # control in a review.
    pod-security.kubernetes.io/enforce: baseline
