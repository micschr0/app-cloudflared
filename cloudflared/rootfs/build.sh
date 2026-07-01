#!/bin/sh
# ==============================================================================
# Home Assistant App (Add-on): Cloudflared
#
# Container build of Cloudflared
# ==============================================================================

set -eux

# yq is to avoid depending on Home Assistant API on startup
apk add --no-cache yq-go="${YQ_VERSION}"

# Adapt the architecture to the cloudflared specific names if needed
# see HA archs: https://developers.home-assistant.io/docs/add-ons/configuration/#:~:text=the%20add%2Don.-,arch,-list
# see Cloudflared archs: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation
case "${BUILD_ARCH}" in
"aarch64")
    cloudflared_arch="arm64"
    ;;
*)
    cloudflared_arch="${BUILD_ARCH}"
    ;;
esac

# Download cloudflared .deb and verify its checksum
deb_file="/tmp/cloudflared.deb"
wget -q -O "$deb_file" \
  "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${cloudflared_arch}.deb"

# Cloudflare publishes SHA256 hashes in the release notes.
# Verify the .deb hash before extracting — same trust anchor (GitHub/HTTPS),
# but protects against corrupted downloads and CDN cache mismatches.
expected_sha256=$(wget -qO- \
  "https://api.github.com/repos/cloudflare/cloudflared/releases/tags/${CLOUDFLARED_VERSION}" \
  | sed -n "s/.*cloudflared-linux-${cloudflared_arch}\\.deb: \\([a-f0-9]\\{64\\}\\).*/\\1/p")
actual_sha256=$(sha256sum "$deb_file" | cut -d' ' -f1)
if [ -z "$expected_sha256" ]; then
  echo "ERROR: could not find expected checksum for cloudflared-linux-${cloudflared_arch}.deb"
  exit 1
fi
if [ "$expected_sha256" != "$actual_sha256" ]; then
  echo "Checksum mismatch!"
  echo "Expected: $expected_sha256"
  echo "Got:      $actual_sha256"
  exit 1
fi
echo "Deb checksum OK: $actual_sha256"

# Extract the cloudflared binary from the .deb (ar archive containing
# control.tar.* and data.tar.*; the binary lives in data.tar.* at
# usr/bin/cloudflared).
cd /tmp
ar x "$deb_file" data.tar.gz
tar -xzf data.tar.gz -C / ./usr/bin/cloudflared
rm -f "$deb_file" data.tar.gz

# Make the downloaded bin executeable
chmod +x /usr/bin/cloudflared

# Remove legacy cont-init.d services
rm -rf /etc/cont-init.d

# Remove s-6 legacy/deprecated (and not needed) services
rm -f /package/admin/s6-overlay/etc/s6-rc/sources/base/contents.d/legacy-cont-init
rm -f /package/admin/s6-overlay/etc/s6-rc/sources/base/contents.d/fix-attrs
rm -f /package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/legacy-services
