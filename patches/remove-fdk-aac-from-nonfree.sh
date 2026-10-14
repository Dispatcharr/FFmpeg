#!/usr/bin/env bash
# Move libfdk_aac out of EXTERNAL_LIBRARY_NONFREE_LIST so a GPL+version3 build
# can link fdk-aac-stripped without --enable-nonfree.
set -euo pipefail

configure_path="${1:-configure}"

if [[ ! -f "$configure_path" ]]; then
  echo "configure not found: $configure_path" >&2
  exit 1
fi

if ! grep -q 'libfdk_aac' "$configure_path"; then
  echo "libfdk_aac not referenced in configure; nothing to patch" >&2
  exit 1
fi

# Delete libfdk_aac from the NONFREE list block only.
awk '
  BEGIN { in_nonfree = 0 }
  /^EXTERNAL_LIBRARY_NONFREE_LIST="/ { in_nonfree = 1 }
  in_nonfree && /^"/ { in_nonfree = 0 }
  in_nonfree && $0 ~ /^[[:space:]]*libfdk_aac[[:space:]]*$/ { next }
  { print }
' "$configure_path" > "${configure_path}.patched"

# If that was the only list entry, put libfdk_aac back outside NONFREE.
# Otherwise --enable-libfdk-aac is an unknown option.
if ! grep -q '^[[:space:]]*libfdk_aac[[:space:]]*$' "${configure_path}.patched"; then
  awk '
    /^[[:space:]]*libdav1d[[:space:]]*$/ && !done {
      print
      print "    libfdk_aac"
      done = 1
      next
    }
    { print }
    END { if (!done) exit 1 }
  ' "${configure_path}.patched" > "${configure_path}.patched2" \
    || { echo "libfdk_aac was only listed in NONFREE, and libdav1d was not found" >&2; exit 1; }
  mv "${configure_path}.patched2" "${configure_path}.patched"
fi

mv "${configure_path}.patched" "$configure_path"
echo "Patched $configure_path: libfdk_aac removed from NONFREE list"
