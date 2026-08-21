#!/bin/sh
# Deliberately insecure chmod forms used only by the Semgrep policy fixture job.
chmod 666 /tmp/semgrep-canonical-666
chmod 777 /tmp/semgrep-canonical-777
chmod 0777 /tmp/semgrep-leading-zero-777
chmod -R 0666 /tmp/semgrep-recursive-leading-zero-666
chmod a+w /tmp/semgrep-symbolic-world-write
