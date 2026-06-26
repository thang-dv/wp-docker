#!/bin/sh
# Manual full plugin sync from plugins.txt and local-plugins/
export WP_FORCE_INSTALL=1
exec /usr/local/bin/install-plugins.sh
