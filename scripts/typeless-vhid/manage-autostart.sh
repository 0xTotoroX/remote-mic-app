#!/bin/bash
# Manage only this personal test integration; never replace pqrs-owned jobs.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin

driver_label=com.sayall.typeless-test.vhid-daemon
bridge_label=com.sayall.typeless-test.bridge
driver='/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon'
bridge=/usr/local/libexec/sayall-vhid-bridge-test
job_dir=/Library/LaunchDaemons

fail() { echo "$*" >&2; exit 1; }
require_root() { [[ $EUID == 0 ]] || fail 'Run install/disable with sudo in Terminal.'; }
validate_uid() {
    [[ ${1:-} =~ ^[1-9][0-9]*$ ]] || fail 'A non-root numeric user ID is required.'
    /usr/bin/id -nu "$1" >/dev/null || fail 'User ID does not exist on this Mac.'
}

render_job() {
    local label=$1 executable=$2 argument=$3 output=$4
    cat > "$output" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>$executable</string>$argument</array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>ExitTimeOut</key><integer>5</integer>
<key>ProcessType</key><string>Interactive</string>
<key>Umask</key><integer>63</integer>
</dict></plist>
EOF
    /usr/bin/plutil -lint "$output"
}

render() {
    validate_uid "$1"
    [[ -d $2 ]] || fail 'Output directory must already exist.'
    render_job "$driver_label" "$driver" '' "$2/$driver_label.plist"
    render_job "$bridge_label" "$bridge" "<string>$1</string>" "$2/$bridge_label.plist"
}

check_root_path() {
    local path=$1 mode
    while [[ $path != / ]]; do
        [[ ! -L $path && -e $path ]] || fail "Missing or symbolic path: $path"
        [[ $(/usr/bin/stat -f %u "$path") == 0 ]] || fail "Not root-owned: $path"
        mode=$(/usr/bin/stat -f %Lp "$path")
        (( (8#$mode & 8#022) == 0 )) || fail "Group/world writable: $path"
        path=$(/usr/bin/dirname "$path")
    done
}

install_jobs() {
    require_root
    validate_uid "$1"
    [[ -x $driver && -x $bridge ]] || fail 'Install the official driver and the test bridge first.'
    check_root_path "$driver"
    check_root_path "$bridge"
    check_root_path "$job_dir"
    /usr/bin/codesign --verify --strict -R '=anchor apple generic and certificate leaf[subject.OU] = "G43BCU2T37"' "${driver%/Contents/MacOS/*}"
    # Do not start a duplicate of a manually launched daemon or bridge.
    for label in "$driver_label" "$bridge_label"; do
        local executable=$bridge
        [[ $label != "$driver_label" ]] || executable=$driver
        if ! /bin/launchctl print "system/$label" >/dev/null 2>&1 &&
           /bin/ps -axo comm= | /usr/bin/grep -Fqx "$executable"; then
            fail "Already running outside our launchd job: $executable"
        fi
    done
    stage=$(/usr/bin/mktemp -d /private/tmp/sayall-autostart.XXXXXX)
    trap '/bin/rm -f "$stage/$driver_label.plist" "$stage/$bridge_label.plist"; /bin/rmdir "$stage"' EXIT
    render "$1" "$stage"
    for label in "$driver_label" "$bridge_label"; do
        local target="$job_dir/$label.plist"
        [[ ! -L $target ]] || fail "Refusing symbolic job file: $target"
        if [[ -e $target ]]; then
            check_root_path "$target"
            /usr/bin/cmp -s "$stage/$label.plist" "$target" || fail "Existing job differs; review it before replacement: $target"
        fi
    done
    for label in "$driver_label" "$bridge_label"; do
        /usr/bin/install -o root -g wheel -m 644 "$stage/$label.plist" "$job_dir/$label.plist"
        /bin/launchctl enable "system/$label"
        if ! /bin/launchctl print "system/$label" >/dev/null 2>&1; then
            /bin/launchctl bootstrap system "$job_dir/$label.plist"
        fi
    done
    echo 'Startup jobs installed. Check status, then test the physical remote. No keys were sent.'
}

case ${1:-status} in
    render) [[ $# == 3 ]] || fail 'Usage: manage-autostart.sh render USER_ID OUTPUT_DIRECTORY'; render "$2" "$3" ;;
    install) [[ $# == 2 ]] || fail 'Usage: sudo manage-autostart.sh install USER_ID'; install_jobs "$2" ;;
    disable)
        require_root
        for label in "$bridge_label" "$driver_label"; do
            /bin/launchctl disable "system/$label"
            if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
                /bin/launchctl bootout "system/$label"
            fi
        done
        echo 'Test startup jobs disabled; installed files and driver preserved.' ;;
    status)
        for label in "$driver_label" "$bridge_label"; do
            echo "--- $label"
            /bin/launchctl print "system/$label" || true
        done
        if [[ -S /var/run/sayall-vhid-bridge.sock ]]; then
            /usr/bin/stat -f '%Su %Sp %N' /var/run/sayall-vhid-bridge.sock
        else
            echo 'Bridge socket absent.'
        fi ;;
    *) fail 'Usage: manage-autostart.sh {status|render USER_ID DIRECTORY|install USER_ID|disable}' ;;
esac
