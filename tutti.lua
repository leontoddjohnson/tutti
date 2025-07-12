mxsamples = include 'mx.samples/lib/mx.samples'
engine.name = "MxSamples"
skeys = mxsamples:new()

N_INSTRUMENTS = 4  -- number of instruments to use

midi_devices = {}  -- MIDI device names, indexed 1-n (for n *connected* devices)
device_midi = {}  -- MIDI connection for device indexed in `midi_devices`
inst_midi = {}  -- MIDI device connections for each instrument
instruments = {}  -- list of downloaded instruments (must be updated)

-- ========================================================================== --
-- INIT                                                                       --
-- ========================================================================== --

function init()
  define_midi()
  update_instruments()

  params:add_separator("instrument <--> midi")
  
  for inst = 1,N_INSTRUMENTS do
    params:add_option(
      "inst_".. inst .. "_name", 
      "inst ".. inst .. " name", 
      instruments, 1)

    params:add_option(
      "inst_".. inst .. "_device", 
      "inst ".. inst .. " device", 
    midi_devices, 2)

    params:add_number(
      "inst_".. inst .. "_channel", 
      "inst ".. inst .. " channel", 
      1, 16, 1)
  end

end


-- ========================================================================== --
-- UTILITY                                                                    --
-- ========================================================================== --

-- add parameters for each instrument
-- (adapted from @schollz's `MxSamples:new` code)
function add_instrument_params()
  local filter_freq = controlspec.new(20,20000,'exp',0,20000,'Hz')
  local delay_rates_names = {
    "whole-note","half-note","quarter note","eighth note","sixteenth note","thirtysecond"}
  local delay_rates = {4,2,1,1/2,1/4,1/8,1/16}

  -- add parameters
  for inst = 1,N_INSTRUMENTS do
    params:add_group("instrument " .. inst, 19)

    params:add {
      type='control',
      id=inst .. "_amp",
      name="amp",
    controlspec=controlspec.new(0,10,'lin',0,1.0,'amp')}
    params:add {
      type='control',
      id=inst .. "_pan",
      name="pan",
    controlspec=controlspec.new(-1,1,'lin',0,0)}
    params:add {
      type='control',
      id=inst .. "_attack",
      name="attack",
    controlspec=controlspec.new(0,10,'lin',0,0,'s')}
    params:add {
      type='control',
      id=inst .. "_decay",
      name="decay",
    controlspec=controlspec.new(0,10,'lin',0,1,'s')}
    params:add {
      type='control',
      id=inst .. "_sustain",
      name="sustain",
    controlspec=controlspec.new(0,2,'lin',0,0.9,'amp')}
    params:add {
      type='control',
      id=inst .. "_release",
      name="release",
    controlspec=controlspec.new(0,10,'lin',0,2,'s')}
    params:add {
      type='control',
      id=inst .. "_transpose_midi",
      name="transpose midi",
    controlspec=controlspec.new(-24,24,'lin',0,0,'note',1/48)}
    params:add {
      type='control',
      id=inst .. "_transpose_sample",
      name="transpose sample",
    controlspec=controlspec.new(-24,24,'lin',0,0,'note',1/48)}
    params:add {
      type='control',
      id=inst .. "_tune",
      name="tune sample",
    controlspec=controlspec.new(-100,100,'lin',0,0,'cents',1/200)}
    params:add {
      type='control',
      id=inst .. "_lpf_mxsamples",
      name='low-pass filter',
      controlspec=filter_freq,
      formatter=Formatters.format_freq}
    params:add {
      type='control',
      id=inst .. "_hpf_mxsamples",
      name='high-pass filter',
      controlspec=controlspec.new(20,20000,'exp',0,20,'Hz'),
      formatter=Formatters.format_freq}
    params:add {
      type='control',
      id=inst .. "_reverb_send",
      name="reverb send",
    controlspec=controlspec.new(0,100,'lin',0,0,'%',1/100)}
    params:add {
      type='control',
      id=inst .. "_delay_send",
      name="delay send",
    controlspec=controlspec.new(0,100,'lin',0,0,'%',1/100)}
    params:add {
      type='control',
      id=inst .. "_sample_start",
      name="sample start",
    controlspec=controlspec.new(0,1000,'lin',0,0,'ms',1/1000)}
    params:add {
      type='control',
      id=inst .. "_play_release",
      name="play release prob",
    controlspec=controlspec.new(0,100,'lin',0,0,'%',1/100)}
    params:add_option(inst .. "_scale_velocity","velocity sensitivity",{"delicate","normal","stiff","fixed"},4)
    params:add_option(inst .. "_pedal_mode","pedal mode",{"sustain","sostenuto"},1)
  end

  params:add {
    type='control',
    id="mxsamples_delay_times",
    name="delay iterations",
  controlspec=controlspec.new(0,100,'lin',0,1,'beats',1/100)}
  params:set_action("mxsamples_delay_times",function(x)
    if engine.name=="MxSamples" then
      engine.mxsamples_delay_feedback(x/100)
    end
  end)
  params:add_option("mxsamples_delay_rate","delay rate",delay_rates_names,1)
  params:set_action("mxsamples_delay_rate",function(x)
    if engine.name=="MxSamples" then
      engine.mxsamples_delay_beats(delay_rates[x])
    end
  end)
end

-- determine connected MIDI devices, and save ID mapping.
function define_midi()
  n = 1 -- device connection index

  for i = 1,16 do
    if midi.devices[i] then
      table.insert(midi_devices, midi.devices[i].name)
      device_midi[n] = midi.connect(midi.devices[i].port)
      device_midi[n].event = function(data)
        local d = midi.to_msg(data)
        local instrument

        for inst=1,N_INSTRUMENTS do
          instrument = params:get("inst_" .. inst .. "_name")

          if d.ch == params:get("inst_" .. inst .. "_channel")
            and n == params:get("inst_" .. inst .. "_device") then
            play_midi(instrument, d)
          end
        end
      end

      n = n + 1
    end
  end
end

-- play MIDI message `data` (`.to_msg`) on the instrument with name `instrument`
-- (adapted from @schollz's `setup_midi` function)
function play_midi(instrument, data)
  if data.type == "note_on" then
    skeys:on({
      name=instrument,
      midi=data.note,
      velocity=data.velocity
    })

  elseif data.type == "note_off" then
    skeys:off({
      name=instrument,
      midi=data.note
    })

  -- sustain pedal
  elseif data.cc == 64 then
    local val = data.val

    if val > 126 then
      val = 1
    else
      val = 0
    end

    if params:get(instrument .. "pedal_mode") == 1 then
      engine.mxsamples_sustain(val)
    else
      engine.mxsamples_sustenuto(val)
    end

  end
end

-- get list of items in a directory
function list_dir(path)
  local items = {}
  local p = io.popen('ls ' .. path)

  if p then
    for item in p:lines() do
      table.insert(items, item)
    end
    p:close()
  end
  return items
end

-- update list of downloaded instruments in `instruments`
function update_instruments()
  local fpath = "/home/we/dust/audio/mx.samples/"
  local possible_instruments = list_dir(fpath)

  for _, inst in ipairs(possible_instruments) do
    local files_for = capture("ls " .. fpath .. inst .. "/*.wav")
    
    if string.find(files_for, ".wav") then
      table.insert(instruments, inst)
    end
  end
end

-- capture the output of a shell command
-- cr: @schollz in https://github.com/schollz/mx.samples
function capture(cmd,raw)
  local f=assert(io.popen(cmd,'r'))
  local s=assert(f:read('*a'))
  f:close()
  if raw then return s end
  s=string.gsub(s,'^%s+','')
  s=string.gsub(s,'%s+$','')
  s=string.gsub(s,'[\n\r]+',' ')
  return s
end

-- ========================================================================== --
-- UI                                                                    --
-- ========================================================================== --
