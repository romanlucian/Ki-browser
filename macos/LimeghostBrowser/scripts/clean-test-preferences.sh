#!/bin/bash
# Removes the preference files the test suite leaves in ~/Library/Preferences.
#
# Each test that needs isolated storage makes its own UserDefaults suite. The
# teardown empties the domain, which is what matters for correctness, but macOS
# writes an empty .plist back when the still-live UserDefaults object is flushed
# as the test process exits. A full run therefore leaves roughly eighty files
# behind, and they accumulate: this repository had gathered several thousand
# before anyone looked.
#
# Run it after `swift test`, or whenever the folder needs tidying. It is safe at
# any time — everything it removes is empty by construction.
#
# What it will never touch: anything beginning `com.clearframe`. That is where
# real data lives — `com.clearframe.browser.plist` holds the app's own settings,
# and `com.clearframe.browser.profile.<uuid>.plist` holds a profile's bookmarks
# and history. A profile suite is only removed when the app itself deletes that
# profile.

set -euo pipefail

PREFERENCES="$HOME/Library/Preferences"

if [ ! -d "$PREFERENCES" ]; then
    echo "No preferences folder at $PREFERENCES; nothing to do."
    exit 0
fi

# `limeghost.<something>.<uuid>.plist`, and only that shape. The leading
# `com.` on real files means they cannot match this pattern.
#
# Written for the bash macOS actually ships, which is 3.2: no mapfile, no
# associative arrays.
removed=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$(basename "$file")" in
        com.*)
            # Cannot happen with the pattern above; refused explicitly anyway,
            # because the cost of being wrong here is somebody's bookmarks.
            echo "Refusing to remove $file" >&2
            exit 1
            ;;
    esac
    rm -f "$file"
    removed=$((removed + 1))
done <<EOF
$(find "$PREFERENCES" -maxdepth 1 -name 'limeghost.*-*.plist' 2>/dev/null || true)
EOF

if [ "$removed" -eq 0 ]; then
    echo "No test preference files to remove."
else
    printf 'Removed %d test preference file(s) from %s\n' "$removed" "$PREFERENCES"
fi
