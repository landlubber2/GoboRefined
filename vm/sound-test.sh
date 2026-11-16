#!/usr/bin/env bash
# Lab test (0.8.5) of gobo-sound-profile (spin/settings/sound-profile.lua + pactl.lua).
#   vm/sound-test.sh          (needs SSH into the VM and the lab user logged in to the desktop)
# 1. the rule against captured `pactl list cards` output (vm/sound-fixtures/): the laptop's SOF
#    card left "off" (the 0.8.4 report), a desktop HDA card + NVIDIA HDMI card, "the user chose
#    off", a USB card with mixed availability + a Bluetooth card, the VM's own card;
# 2. the VM's real card: --dry-run and --once change nothing;
# 3. the watcher in the session: the VM's card re-created by PulseAudio with profile "off"
#    (module-alsa-card profile=off, as on the laptop) is switched on and becomes the default;
#    a card switched off by the user is remembered and left off; a Bluetooth output
#    (a null sink named bluez_sink.*) becomes the default and the default falls back after it.
# The files are copied into the VM's /tmp; the installed system is not changed (PulseAudio of
# the lab user is restarted at the end).
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S() { "$here/ssh.sh" "$1"; }
L() { S "su lab -c 'cd /tmp; LC_ALL=C $1' 2>&1"; }   # as the desktop user
pass=0 fail=0
ok() { if echo "$2" | grep -q -- "$3"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1: got [$2], want /$3/"; fail=$((fail+1)); fi; }
no() { if echo "$2" | grep -q -- "$3"; then echo "FAIL $1: got [$2], must not match /$3/"; fail=$((fail+1)); else echo "PASS $1"; pass=$((pass+1)); fi; }

(cd "$here/.." && tar cf - spin/settings/pactl.lua spin/settings/sound-profile.lua vm/sound-fixtures) |
   S 'rm -rf /tmp/soundtest && mkdir -p /tmp/soundtest && tar xf - -C /tmp/soundtest && chown -R lab /tmp/soundtest'
D=/tmp/soundtest
SP="lua $D/spin/settings/sound-profile.lua"
F=$D/vm/sound-fixtures
LAPTOP=alsa_card.pci-0000_00_1f.3-platform-skl_hda_dsp_generic

echo "== 1. the rule on captured output"
out=$(L "$SP --fixture $F/laptop-sof-off.cards --choices /nonexistent")
ok "laptop SOF card off -> HiFi (none available: highest priority)" "$out" "card $LAPTOP: off -> HiFi (Play HiFi quality Music; no profile is marked available"
ok "laptop: the command it would run" "$out" "would run: pactl set-card-profile '$LAPTOP' 'HiFi'"
out=$(L "$SP --fixture $F/laptop-sof-off.cards --choices $F/user-chose-off.choices")
ok "laptop, user chose off -> left alone" "$out" "left alone (the user chose \"off\")"
no "laptop, user chose off -> nothing run" "$out" "would run"
out=$(L "$SP --fixture $F/desktop-hda-nvidia.cards --choices /nonexistent")
ok "desktop HDA (duplex active) -> left alone" "$out" "alsa_card.pci-0000_00_1f.3: left alone (profile \"output:analog-stereo+input:analog-stereo\" is active)"
ok "desktop NVIDIA HDMI-only card off -> left alone" "$out" "alsa_card.pci-0000_01_00.1: left alone (only HDMI"
no "desktop: nothing run" "$out" "would run"
out=$(L "$SP --fixture $F/usb-off-mixed.cards --choices /nonexistent")
ok "USB card: available profile wins over higher-priority unavailable one" "$out" "usb-Generic_USB_Audio-00: off -> output:analog-stereo (Analog Stereo Output; best available profile)"
ok "Bluetooth card -> left to the Bluetooth policy" "$out" "bluez_card.00_11_22_33_44_55: left alone (Bluetooth device"
out=$(L "$SP --fixture $F/vm-ac97.cards --choices /nonexistent")
ok "VM card (captured) -> left alone" "$out" "left alone (profile \"output:analog-stereo+input:analog-stereo\" is active)"
no "VM card (captured): nothing run" "$out" "would run"

echo "== 2. the VM's real card"
before=$(L "pactl list cards | grep 'Active Profile'; pactl info | grep 'Default Sink'")
out=$(L "$SP --dry-run")
ok "--dry-run on the VM: left alone" "$out" "alsa_card.pci-0000_00_05.0: left alone"
no "--dry-run on the VM: nothing run" "$out" "would run"
L "rm -f /Users/lab/.cache/gobo-sound-profile.log"
out=$(L "$SP --once")
ok "--once on the VM: left alone" "$out" "left alone"
after=$(L "pactl list cards | grep 'Active Profile'; pactl info | grep 'Default Sink'")
ok "--once changed nothing (profile, default output)" "$([ "$before" = "$after" ] && echo same || echo "differs: $before / $after")" "^same$"

echo "== 3. the watcher in the session"
CH=$D/choices
# the session's own watcher (installed system) would act too: stopped here, started again at the end
L "pkill -u lab -f \"[g]obo-settings/sound-profile.lua\"" > /dev/null
L "rm -f $CH; ($SP --choices $CH > /dev/null 2>&1 &) ; sleep 2; pgrep -u lab -f \"[s]ound-profile.lua --choices\" | head -n 1" > /dev/null
mod=$(L "pactl list short modules" | awk '$2 == "module-alsa-card" { print $1; exit }')
L "pactl unload-module $mod; sleep 1; pactl load-module module-alsa-card device_id=0 name=pci-0000_00_05.0 card_name=alsa_card.pci-0000_00_05.0 profile=off tsched=yes use_ucm=yes > /dev/null; sleep 3" > /dev/null
ok "card re-created as off -> switched on by the watcher" "$(L "pactl list cards | grep 'Active Profile'")" "Active Profile: output:analog-stereo+input:analog-stereo"
ok "default output is the card again (was the null sink)" "$(L "pactl info | grep 'Default Sink'")" "alsa_output.pci-0000_00_05.0.analog-stereo"
ok "watcher log names the switch" "$(L "cat /Users/lab/.cache/gobo-sound-profile.log")" "off -> output:analog-stereo+input:analog-stereo"
L "pactl set-card-profile alsa_card.pci-0000_00_05.0 off; sleep 3" > /dev/null
ok "user switched the card off -> stays off" "$(L "pactl list cards | grep 'Active Profile'")" "Active Profile: off"
ok "user's off remembered" "$(L "cat $CH")" "alsa_card.pci-0000_00_05.0.off"
L "pactl set-card-profile alsa_card.pci-0000_00_05.0 output:analog-stereo+input:analog-stereo; sleep 2" > /dev/null
L "pactl load-module module-null-sink sink_name=bluez_sink.00_11_22_33_44_55.a2dp_sink > /dev/null; sleep 3" > /dev/null
ok "Bluetooth output appears -> default" "$(L "pactl info | grep 'Default Sink'")" "bluez_sink.00_11_22_33_44_55"
nm=$(L "pactl list short modules" | awk '$2 == "module-null-sink" { print $1; exit }')
L "pactl unload-module $nm; sleep 2" > /dev/null
ok "Bluetooth output gone -> default falls back to the card" "$(L "pactl info | grep 'Default Sink'")" "alsa_output.pci-0000_00_05.0.analog-stereo"
L "pkill -u lab -f \"[s]ound-profile.lua --choices\"; pulseaudio -k; sleep 2; pulseaudio --start; sleep 2" > /dev/null
L "[ -x /System/Index/bin/gobo-sound-profile ] && (DISPLAY=:0 gobo-sound-profile > /dev/null 2>&1 &)" > /dev/null
ok "PulseAudio restarted, card on its normal profile" "$(L "pactl list cards | grep 'Active Profile'")" "output:analog-stereo+input:analog-stereo"
S "rm -rf $D"
echo "passed $pass, failed $fail"
