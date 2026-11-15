-- Sound: opens the sound control (PulseAudio Volume Control).
local P = { id = "sound", title = "Sound", icon = "audio-volume-high" }

function P.build(C)
   local outer, box = C.page("Sound", "Volume of each program, output device (speakers, headphones, HDMI) and microphone.")
   local sink = C.pread("pactl info"):match("Default Sink: ([^\n]+)")
   if sink then box:pack_start(C.text("Sound goes to: " .. sink), false, false, 0) end
   box:pack_start(C.button("Open the sound control", function() C.spawn({ "pavucontrol" }) end, "suggested-action"), false, false, 0)
   box:pack_start(C.text("The volume can also be changed with the speaker icon on the taskbar.", "dim-label"), false, false, 0)
   return outer
end

return P
