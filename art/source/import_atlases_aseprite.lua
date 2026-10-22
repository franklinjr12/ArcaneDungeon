-- Build editable Aseprite art sources for all non-character atlas families.
-- The generated Python PNGs are reproducible runtime baselines, not raster-editing restrictions.
local project=app.params["project"]
if not project then error("project required") end
local root=project.."\\assets\\pixel\\"
local out=project.."\\art\\aseprite\\"
local flat={"dungeon_tiles","dungeon_props","rune_icons","spell_effects","panel_frame","button_frame","menu_background"}
for _,name in ipairs(flat) do
  local source=app.open(root..name..".png")
  if not source then error("missing "..name) end
  app.sprite=source
  app.command.SaveFileAs{filename=out..name..".aseprite"}
  source:close()
  print("ASEPRITE_ATLAS "..name)
end
local fx=app.open(root.."spell_effects.png")
if not fx then error("missing effect atlas") end
local original=Image(fx.spec.width,fx.spec.height,ColorMode.RGB)
original:drawSprite(fx,1)
local types={"fire","water","lightning","orb","enemy","arc","impact","dodge"}
for y,name in ipairs(types) do
  local s=Sprite(32,32,ColorMode.RGB)
  s.layers[1].name=name.." / pixel VFX"
  app.transaction(function()
    for x=1,8 do
      if x>1 then s:newFrame() end
      local tile=Image(32,32,ColorMode.RGB)
      tile:drawImage(original,Point(-(x-1)*32,-(y-1)*32))
      s:newCel(s.layers[1],x,tile,Point(0,0))
      s.frames[x].duration=0.075
    end
    local tag=s:newTag(1,8)
    tag.name="cycle"
  end)
  app.sprite=s
  app.command.SaveFileAs{filename=out.."vfx_"..name..".aseprite"}
  s:close()
  print("ASEPRITE_VFX "..name)
end
fx:close()
