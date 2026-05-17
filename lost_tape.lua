-- lost_tape.lua  V1.0
-- Synthétiseur granulaire ambient pour Norns Shield
-- Inspiré du LemonDrop (1010 Music)
--
-- Pages  : E1 navigation | K3 master play/stop
-- Grains : E2 params | E3 valeur | K2 reset
-- Delay  : E2 params | E3 valeur | K2 reset
-- Tape   : E2 params | E3 valeur | K2 reset
-- Seq    : E2 curseur | E3 note  | K2 gate on/off | K3 play seq

engine.name = "Granular"

-- Waveform ---------------------------------------------------
local wv_data = {}
local wv_loaded = false
local wv_filename = "NO SAMPLE"
local WV_TOP = 10
local WV_BOT = 25
local WV_H   = WV_BOT - WV_TOP

local function u16le(s) local a,b=s:byte(1,2); return a+b*256 end
local function i16le(s) local v=u16le(s); return v>=32768 and v-65536 or v end
local function u32le(s) local a,b,c,d=s:byte(1,4); return a+b*256+c*65536+d*16777216 end

local function wv_load(path)
  if not path or path=="" then return end
  local f=io.open(path,"rb"); if not f then return end
  if f:read(4)~="RIFF" then f:close();return end; f:read(4)
  if f:read(4)~="WAVE" then f:close();return end
  local bd,ba,ds,dst
  while true do
    local id=f:read(4); if not id or #id<4 then break end
    local sz=u32le(f:read(4))
    if id=="fmt " then
      local d=f:read(sz); if not d or #d<16 then break end
      ba=u16le(d:sub(13,14)); bd=u16le(d:sub(15,16))
    elseif id=="data" then ds=sz; dst=f:seek(); break
    else f:read(sz+(sz%2)) end
  end
  if not dst or (bd~=16 and bd~=24) then
    f:close(); for i=1,128 do wv_data[i]=0.05 end; wv_loaded=true; return
  end
  local bps=bd//8; local nf=math.floor(ds/ba); if nf<2 then f:close();return end
  local mx=0.0001
  for i=1,128 do
    local fi=math.floor((i-1)/127*(nf-1))
    f:seek("set",dst+fi*ba)
    local by=f:read(bps); if not by or #by<bps then break end
    local s=0.0
    if bd==16 then s=math.abs(i16le(by))/32768.0
    else local b1,b2,b3=by:byte(1,3); local r=b1+b2*256+b3*65536
      if r>=8388608 then r=r-16777216 end; s=math.abs(r)/8388608.0 end
    wv_data[i]=s; if s>mx then mx=s end
  end
  f:close()
  for i=1,128 do wv_data[i]=(wv_data[i] or 0)/mx end
  wv_loaded=true
  local nm=(path:match("([^/]+)$") or path):gsub("%.[^.]+$","")
  if #nm>14 then nm=nm:sub(1,12)..".." end
  wv_filename=string.upper(nm)
end

local function wv_draw(lv)
  if not wv_loaded then return end
  screen.level(lv or 5)
  for x=0,127 do
    local h=math.max(1,math.floor((wv_data[x+1] or 0)*WV_H))
    screen.rect(x,WV_BOT-h,1,h); screen.fill()
  end
end

local function wv_cursor(pos,lv)
  screen.level(lv or 15)
  screen.rect(math.floor(pos*127),WV_TOP,1,WV_H); screen.fill()
end

-- Delay musical values (avant fmt_val) ----------------------
local DEL_NOTES = {
  {beats=0.25, name="1/16"}, {beats=0.5,  name="1/8"},
  {beats=0.75, name="3/16"}, {beats=1.0,  name="1/4"},
  {beats=1.5,  name="3/8"},  {beats=2.0,  name="1/2"},
  {beats=3.0,  name="3/4"},  {beats=4.0,  name="1 BAR"},
}

local function del_secs(idx)
  local ok,bpm=pcall(function() return params:get("clock_tempo") end)
  local b=(ok and bpm and bpm>0) and bpm or 120
  return DEL_NOTES[util.clamp(math.floor(idx),1,#DEL_NOTES)].beats*(60.0/b)
end

-- Formatage -------------------------------------------------
local function fmt_val(p)
  if p.fmt=="rev"      then return p.val>0.5 and "ON" or "OFF" end
  if p.fmt=="del_note" then return DEL_NOTES[util.clamp(math.floor(p.val),1,#DEL_NOTES)].name end
  if p.fmt=="hz" then
    local v=p.val
    if v>=10000 then return string.format("%.0fK",v/1000)
    elseif v>=1000 then return string.format("%.1fK",v/1000)
    else return string.format("%.0f",v) end
  end
  return string.format(p.fmt,p.val)
end

-- Gammes ----------------------------------------------------
local SCALES = {
  {name="MAJOR",     iv={0,2,4,5,7,9,11}},
  {name="MINOR",     iv={0,2,3,5,7,8,10}},
  {name="PENTA MAJ", iv={0,2,4,7,9}},
  {name="PENTA MIN", iv={0,3,5,7,10}},
  {name="DORIAN",    iv={0,2,3,5,7,9,10}},
  {name="LYDIAN",    iv={0,2,4,6,7,9,11}},
  {name="MIXO",      iv={0,2,4,5,7,9,10}},
  {name="CHROMATIC", iv={0,1,2,3,4,5,6,7,8,9,10,11}},
}
local ROOT_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local SCALE_NAMES = {}; for _,s in ipairs(SCALES) do table.insert(SCALE_NAMES,s.name) end
local cur_scale=1; local cur_root=0; local cur_octave=0

local function deg_st(deg)
  local sc=SCALES[cur_scale].iv; local n=#sc
  local oct=math.floor(deg/n); local d=deg-oct*n
  if d<0 then d=d+n; oct=oct-1 end
  return cur_root+sc[d+1]+(oct+cur_octave)*12
end
local function deg_ratio(deg) return 2^(deg_st(deg)/12) end
local function deg_note(deg)
  local st=deg_st(deg)
  return ROOT_NAMES[((st%12)+12)%12+1]..tostring(math.floor(st/12)+4)
end
local function scale_len() return #SCALES[cur_scale].iv end

-- Pages -----------------------------------------------------
local PAGE_NAMES = {"GRAINS","DELAY","TAPE","SEQ"}
local page = 1

-- Play/stop -------------------------------------------------
local playing = true
local function set_engine(state)
  playing=state
  if playing then engine.amp(param_by_id and param_by_id["amp"].val or 0.8)
  else engine.amp(0.0) end
end

-- Params ----------------------------------------------------
local PARAMS_GRAINS = {
  {id="pos",        name="POS",     min=0.0, max=1.0,  step=0.005,default=0.5, val=0.5, fmt="%.3f"},
  {id="size",       name="SIZE",    min=0.01,max=1.0,  step=0.01, default=0.1, val=0.1, fmt="%.2f"},
  {id="density",    name="DENSITY", min=0.5, max=15.0, step=0.5,  default=8.0, val=8.0, fmt="%.1f"},
  {id="pitch",      name="PITCH",   min=0.1, max=2.0,  step=0.01, default=1.0, val=1.0, fmt="%.2f"},
  {id="pan",        name="PAN",     min=-1.0,max=1.0,  step=0.01, default=0.0, val=0.0, fmt="%.2f"},
  {id="jitter",     name="JITTER",  min=0.0, max=0.5,  step=0.005,default=0.0, val=0.0, fmt="%.3f"},
  {id="spread",     name="SPREAD",  min=0.0, max=1.0,  step=0.01, default=0.0, val=0.0, fmt="%.2f"},
  {id="env_attack", name="ENV ATK", min=0.0, max=0.49, step=0.01, default=0.1, val=0.1, fmt="%.2f"},
  {id="env_release",name="ENV REL", min=0.0, max=0.49, step=0.01, default=0.3, val=0.3, fmt="%.2f"},
  {id="amp",        name="AMP",     min=0.0, max=1.0,  step=0.01, default=0.8, val=0.8, fmt="%.2f"},
  {id="reverse",    name="REVERSE", min=0,   max=1,    step=1,    default=0,   val=0,   fmt="rev"},
}
local PARAMS_DELAY = {
  {id="del_time",name="DEL TIME",min=1,   max=8,    step=1,    default=4,   val=4,   fmt="del_note"},
  {id="del_fb",  name="FEEDBACK",min=0.0, max=0.95, step=0.01, default=0.4, val=0.4, fmt="%.2f"},
  {id="del_mix", name="DEL MIX", min=0.0, max=1.0,  step=0.01, default=0.3, val=0.3, fmt="%.2f"},
  {id="rev_size",name="REV SIZE",min=0.0, max=1.0,  step=0.01, default=0.5, val=0.5, fmt="%.2f"},
  {id="rev_damp",name="REV DAMP",min=0.0, max=1.0,  step=0.01, default=0.5, val=0.5, fmt="%.2f"},
  {id="rev_mix", name="REV MIX", min=0.0, max=1.0,  step=0.01, default=0.2, val=0.2, fmt="%.2f"},
}
local PARAMS_TAPE = {
  {id="filt_hz",   name="FILT HZ",  min=200, max=20000,step=200,  default=20000,val=20000,fmt="hz"},
  {id="filt_res",  name="FILT RES", min=0.0, max=1.0,  step=0.01, default=0.0,  val=0.0,  fmt="%.2f"},
  {id="wow",       name="WOW",      min=0.0, max=1.0,  step=0.01, default=0.0,  val=0.0,  fmt="%.2f"},
  {id="flutter",   name="FLUTTER",  min=0.0, max=1.0,  step=0.01, default=0.0,  val=0.0,  fmt="%.2f"},
  {id="tape_sat",  name="SATURATE", min=0.0, max=1.0,  step=0.01, default=0.0,  val=0.0,  fmt="%.2f"},
  {id="tape_noise",name="NOISE",    min=0.0, max=1.0,  step=0.01, default=0.0,  val=0.0,  fmt="%.2f"},
  {id="tape_lp",   name="LOFI HZ",  min=500, max=20000,step=200,  default=20000,val=20000, fmt="hz"},
}

local PAGE_PARAMS = {PARAMS_GRAINS, PARAMS_DELAY, PARAMS_TAPE, {}}
local page_sel = {1,1,1,1}
local function cur_params() return PAGE_PARAMS[page] or {} end
local function get_sel()    return page_sel[page] or 1 end
local function set_sel(v)   page_sel[page]=util.clamp(v,1,math.max(1,#cur_params())) end

param_by_id = {}
local function rebuild_pbid()
  param_by_id={}
  for _,pl in ipairs(PAGE_PARAMS) do
    for _,p in ipairs(pl) do param_by_id[p.id]=p end
  end
end
rebuild_pbid()

-- Sparks (grains visuels) -----------------------------------
local SPARKS_MAX  = 10
local SPARK_H_MAX = 12
local sparks      = {}
local last_gt     = 0

local function update_sparks()
  if not playing or not wv_loaded then return end
  local t  = util.time()
  local iv = 1.0/param_by_id["density"].val
  if (t-last_gt)>=iv and #sparks<SPARKS_MAX then
    last_gt=t
    local j=(math.random()*2-1)*param_by_id["jitter"].val
    local gx=util.clamp(math.floor((param_by_id["pos"].val+j)*127),0,127)
    table.insert(sparks,{x=gx,born=t,max_life=math.max(param_by_id["size"].val,0.05)})
  end
  local now=util.time(); local alive={}
  for _,s in ipairs(sparks) do
    if (now-s.born)<s.max_life then table.insert(alive,s) end
  end
  sparks=alive
end

local function draw_sparks()
  local now=util.time()
  for _,s in ipairs(sparks) do
    local r=1-(now-s.born)/s.max_life
    screen.level(math.min(15,math.max(1,math.floor(r*12)+3)))
    screen.rect(s.x,WV_BOT-math.max(3,math.floor(r*SPARK_H_MAX)),1,math.max(3,math.floor(r*SPARK_H_MAX)))
    screen.fill()
  end
end

-- Visuels pages ---------------------------------------------
local function draw_grains_visual()
  local pos=param_by_id["pos"].val
  local sz=param_by_id["size"].val
  local px=math.floor(pos*127)
  local sz_px=math.max(2,math.floor(sz*45))
  screen.level(2)
  screen.rect(math.max(0,px-sz_px),WV_TOP,math.min(px,px+sz_px)-math.max(0,px-sz_px),WV_H); screen.fill()
  screen.rect(px+1,WV_TOP,math.min(127,px+sz_px)-px,WV_H); screen.fill()
  wv_draw(5)
  draw_sparks()
  local pulse=math.abs(math.sin(util.time()*param_by_id["density"].val*math.pi))
  wv_cursor(pos, math.floor(10+pulse*5))
end

local function draw_delay_visual()
  wv_draw(3)
  local pos=param_by_id["pos"].val
  local px=math.floor(pos*127)
  local dfb=param_by_id["del_fb"].val
  local dpx=math.floor(4+del_secs(param_by_id["del_time"].val)*36)
  local tn=util.time()
  for n=4,1,-1 do
    local b=math.floor(dfb^n*15); if b>=1 then
      local ex=px+dpx*n
      local drift=math.floor(math.sin(tn*1.1+n*0.9)*1.8)
      if ex<=127 then
        local top=util.clamp(WV_TOP+math.max(0,drift),WV_TOP,WV_BOT-2)
        local bot=util.clamp(WV_BOT+math.min(0,drift),WV_TOP+2,WV_BOT)
        screen.level(b); screen.rect(ex,top,1,bot-top); screen.fill()
      end
    end
  end
  wv_cursor(pos,15)
end

local function draw_tape_visual()
  local cy   = math.floor((WV_TOP+WV_BOT)/2)
  local wow  = param_by_id["wow"].val
  local flut = param_by_id["flutter"].val
  local sat  = param_by_id["tape_sat"].val
  local nz   = param_by_id["tape_noise"].val
  local lp   = param_by_id["tape_lp"].val
  local tn   = util.time()
  wv_draw(2)
  if sat>0.05 then
    for w=1,math.floor(sat*5) do
      screen.level(math.max(1,5-w))
      screen.rect(0,cy-w,128,1); screen.fill()
      screen.rect(0,cy+w,128,1); screen.fill()
    end
  end
  for x=0,127 do
    local y=util.clamp(cy+math.floor(
      math.sin(tn*0.8+x*0.03)*wow*3.5+
      math.sin(tn*6.3+x*0.15)*flut*1.5+
      math.sin(tn*11+x*0.22)*flut*0.8
    ),WV_TOP,WV_BOT-1)
    screen.level(math.min(15,math.floor(13+sat*2)))
    screen.rect(x,y-math.floor((1+math.floor(sat*2))/2),1,1+math.floor(sat*2)); screen.fill()
  end
  if lp<19000 then
    local lx=math.floor((lp-500)/(20000-500)*127)
    screen.level(7); screen.rect(lx,WV_TOP,1,WV_H); screen.fill()
  end
  if sat>0.6 then
    screen.level(math.min(15,math.floor((sat-0.6)/0.4*12)+3))
    screen.rect(123,WV_TOP,4,4); screen.fill()
  end
  local seed=math.floor(tn*11); local np=math.floor(nz*15)
  for i=1,np do
    local nx=math.floor(((seed*197+i*67)%128+128)%128)
    local ny=WV_TOP+math.floor(((seed*131+i*59)%WV_H+WV_H)%WV_H)
    screen.level(math.floor(2+((seed*83+i*37)%6))); screen.rect(nx,ny,1,1); screen.fill()
  end
end

-- Séquenceur ------------------------------------------------
local SEQ_DIVS = {
  {beats=0.25,name="1/4"},   {beats=0.5,name="1/2"},
  {beats=1.0,name="1 BAR"},  {beats=2.0,name="2 BAR"},
  {beats=4.0,name="4 BAR"},  {beats=8.0,name="8 BAR"},
}
local seq_steps = {}; for i=1,16 do seq_steps[i]={gate=false,pitch_deg=0} end
local seq_playing = false
local seq_pos     = 0
local seq_cursor  = 1
local seq_length  = 8
local seq_div_idx = 3
local seq_coro    = nil

local function seq_start()
  if seq_coro then clock.cancel(seq_coro) end
  seq_pos=0
  seq_coro=clock.run(function()
    -- Déclenche le step 1 immédiatement
    seq_pos=1
    local first=seq_steps[seq_pos]
    if first.gate then
      local ratio=deg_ratio(first.pitch_deg)
      engine.pitch(ratio)
      if param_by_id["pitch"] then param_by_id["pitch"].val=ratio end
    end
    while true do
      clock.sync(SEQ_DIVS[seq_div_idx].beats)
      seq_pos=(seq_pos%seq_length)+1
      local step=seq_steps[seq_pos]
      if step.gate then
        local ratio=deg_ratio(step.pitch_deg)
        engine.pitch(ratio)
        if param_by_id["pitch"] then param_by_id["pitch"].val=ratio end
      end
    end
  end)
end

local function seq_stop()
  if seq_coro then clock.cancel(seq_coro); seq_coro=nil end
  seq_pos=0
end

local function toggle_master()
  local ns=not playing
  set_engine(ns); seq_playing=ns
  if ns then seq_start() else seq_stop() end
end

local function draw_seq_visual()
  local n=scale_len(); local cw=math.floor(128/seq_length)
  for i=1,seq_length do
    local step=seq_steps[i]; local cx=(i-1)*cw
    local is_pl=(i==seq_pos and seq_playing)
    local is_cur=(i==seq_cursor)
    screen.level(step.gate and (is_pl and 5 or 2) or (is_pl and 3 or 1))
    screen.rect(cx,WV_TOP,cw-1,WV_H); screen.fill()
    if step.gate then
      local bh=math.max(2,math.floor(step.pitch_deg/math.max(n-1,1)*(WV_H-3))+2)
      screen.level(is_pl and 15 or 12)
      screen.rect(cx,WV_BOT-bh,cw-1,bh); screen.fill()
    end
    if is_cur then
      screen.level(step.gate and 15 or 8)
      screen.rect(cx,WV_TOP,cw-1,1); screen.fill()
      screen.rect(cx,WV_BOT-1,cw-1,1); screen.fill()
    end
    if is_pl then
      screen.level(15); screen.rect(cx,WV_BOT-1,cw-1,1); screen.fill()
    end
  end
end

-- Header ----------------------------------------------------
local function draw_header()
  screen.font_size(7); screen.level(8)
  screen.move(2,7); screen.text(wv_filename)
  if playing then
    screen.level(15); screen.move(119,2); screen.line(119,8)
    screen.line(124,5); screen.close(); screen.fill()
  else
    screen.level(5); screen.rect(119,2,6,6); screen.fill()
  end
  if page==4 then
    local ok,v=pcall(function() return params:get("clock_tempo") end)
    screen.level(10); screen.font_size(7)
    screen.move(72,7); screen.text((ok and v) and string.format("%.0fBPM",v) or "CLK")
  end
  for i=1,4 do
    local dx=100+(i-1)*4; screen.level(i==page and 12 or 3)
    if i==page then screen.rect(dx,3,3,3) else screen.rect(dx,4,2,2) end
    screen.fill()
  end
  screen.level(2); screen.move(0,9); screen.line(128,9); screen.stroke()
end

-- Params zone -----------------------------------------------
local function draw_params()
  screen.font_size(7)
  if page==4 then
    local step=seq_steps[seq_cursor]
    screen.level(3); screen.rect(0,27,128,9); screen.fill()
    screen.level(15)
    screen.move(3,35); screen.text("STEP "..string.format("%02d",seq_cursor))
    screen.move(60,35); screen.text(deg_note(step.pitch_deg))
    screen.level(step.gate and 15 or 4)
    screen.move(95,35); screen.text(step.gate and "ON" or "--")
    if seq_playing and seq_pos>0 then
      screen.level(6); screen.move(126,35); screen.text_right(">"..tostring(seq_pos))
    end
    screen.level(4); screen.font_size(7)
    screen.move(3,47); screen.text(ROOT_NAMES[cur_root+1].." "..SCALES[cur_scale].name)
    screen.move(126,47); screen.text_right(seq_length.." STEPS")
    screen.move(3,59); screen.text("DIV "..SEQ_DIVS[seq_div_idx].name)
    screen.level(seq_playing and 12 or 4)
    screen.move(126,59); screen.text_right(seq_playing and "PLAY" or "STOP")
  else
    local pl=cur_params(); local sel=get_sel()
    for row=0,2 do
      local idx=sel+row; if idx>#pl then break end
      local p=pl[idx]; local is_sel=(idx==sel)
      local yt=27+row*12
      if is_sel then screen.level(3); screen.rect(0,yt,128,9); screen.fill() end
      screen.level(is_sel and 15 or 4)
      screen.move(3,yt+8); screen.text(p.name)
      screen.move(125,yt+8); screen.text_right(fmt_val(p))
      local fw=math.floor((p.val-p.min)/(p.max-p.min)*128)
      screen.level(is_sel and 2 or 1); screen.rect(0,yt+9,128,3); screen.fill()
      if fw>0 then screen.level(is_sel and 14 or 6); screen.rect(0,yt+9,fw,3); screen.fill() end
    end
  end
end

-- Metro -----------------------------------------------------
local anim_metro

-- Init ------------------------------------------------------
function init()
  params:add_separator("LOST TAPE")
  params:add_file("sample","sample",_path.audio)
  params:set_action("sample",function(val)
    if not val or val=="" then return end
    engine.read_buf(val)
    clock.run(function() clock.sleep(0.5); wv_load(val); redraw() end)
  end)

  local all={}
  for _,pl in ipairs({PARAMS_GRAINS,PARAMS_DELAY,PARAMS_TAPE}) do
    for _,p in ipairs(pl) do table.insert(all,p) end
  end
  for _,p in ipairs(all) do
    local _p=p
    params:add_control(_p.id,_p.name,
      controlspec.new(_p.min,_p.max,"lin",_p.step,_p.default,""))
    params:set_action(_p.id,function(val)
      _p.val=val
      if _p.id=="amp" then
        if playing then engine.amp(val) end
      elseif _p.id=="del_time" then
        engine.del_time(del_secs(val))
      else
        if engine[_p.id] then engine[_p.id](val) end
      end
    end)
  end

  params:add_separator("SEQUENCEUR")
  params:add_number("seq_length","SEQ LENGTH",2,16,8)
  params:set_action("seq_length",function(v)
    seq_length=v; seq_cursor=util.clamp(seq_cursor,1,seq_length)
    if seq_playing then seq_stop(); seq_start() end
  end)
  params:add_option("seq_div","SEQ DIV",{"1/4","1/2","1 BAR","2 BAR","4 BAR","8 BAR"},3)
  params:set_action("seq_div",function(v) seq_div_idx=v end)
  params:add_option("seq_scale","SEQ SCALE",SCALE_NAMES,1)
  params:set_action("seq_scale",function(v) cur_scale=v end)
  params:add_number("seq_root","SEQ ROOT",0,11,0)
  params:set_action("seq_root",function(v) cur_root=v end)
  params:add_number("seq_octave","SEQ OCTAVE",-2,2,0)
  params:set_action("seq_octave",function(v) cur_octave=v end)

  anim_metro=metro.init(function() update_sparks(); redraw() end, 1/20, -1)
  anim_metro:start()
  params:read(); params:bang()
end

-- Encodeurs -------------------------------------------------
function enc(n,d)
  if n==1 then
    local np=page+(d>0 and 1 or -1)
    if np<1 then np=#PAGE_NAMES end
    if np>#PAGE_NAMES then np=1 end
    page=np; redraw()
  elseif n==2 then
    if page==4 then
      seq_cursor=util.clamp(seq_cursor+(d>0 and 1 or -1),1,seq_length)
    else
      local pl=cur_params(); if #pl>0 then set_sel(get_sel()+(d>0 and 1 or -1)) end
    end
    redraw()
  elseif n==3 then
    if page==4 then
      local step=seq_steps[seq_cursor]
      step.pitch_deg=util.clamp(step.pitch_deg+(d>0 and 1 or -1),0,scale_len()-1)
      -- Preview audio uniquement si on edite le step en cours de lecture
      if seq_cursor==seq_pos then
        local ratio=deg_ratio(step.pitch_deg)
        engine.pitch(ratio)
        if param_by_id["pitch"] then param_by_id["pitch"].val=ratio end
      end
      redraw()
    else
      local pl=cur_params(); if #pl>0 then
        local p=pl[get_sel()]
        if p then params:set(p.id,util.clamp(p.val+d*p.step,p.min,p.max)) end
      end
    end
  end
end

-- Keys ------------------------------------------------------
function key(n,z)
  if z~=1 then return end
  if n==3 then toggle_master(); redraw(); return end
  if page==4 then
    if n==2 then
      seq_steps[seq_cursor].gate=not seq_steps[seq_cursor].gate
      if seq_steps[seq_cursor].gate and seq_cursor==seq_pos then
        local ratio=deg_ratio(seq_steps[seq_cursor].pitch_deg)
        engine.pitch(ratio)
        if param_by_id["pitch"] then param_by_id["pitch"].val=ratio end
      end
      redraw()
    end
  else
    if n==2 then
      local pl=cur_params(); if #pl>0 then
        local p=pl[get_sel()]; if p then params:set(p.id,p.default) end
      end
    end
    redraw()
  end
end

-- Redraw ----------------------------------------------------
function redraw()
  screen.clear(); screen.aa(0); screen.font_face(0)
  draw_header()
  if     page==1 then draw_grains_visual()
  elseif page==2 then draw_delay_visual()
  elseif page==3 then draw_tape_visual()
  elseif page==4 then draw_seq_visual()
  end
  screen.level(2); screen.move(0,26); screen.line(128,26); screen.stroke()
  draw_params()
  screen.update()
end

-- Cleanup ---------------------------------------------------
function cleanup()
  if anim_metro then anim_metro:stop() end
  seq_stop()
end
