-- Split generated horizontal PNG strips into actual Aseprite frames and tags.
-- Usage: aseprite -b --script art/source/import_aseprite.lua --script-param project=C:\Repos\ArcaneDungeon
local project = app.params["project"]
if project == nil then error("project script-param required") end
local root = project .. "\\assets\\pixel\\"
local dest = project .. "\\art\\aseprite\\"
local specs = {
 {id="mage",w=48,h=56}, {id="pursuer",w=48,h=56}, {id="ranged",w=48,h=56},
 {id="flanker",w=48,h=56}, {id="boss",w=104,h=112}, {id="dummy",w=48,h=56}
}
for _,spec in ipairs(specs) do
  local src = app.open(root .. spec.id .. "_sheet.png")
  if not src then error("could not read " .. spec.id) end
  local image = Image(src.spec.width,src.spec.height,ColorMode.RGB)
  image:drawSprite(src,1)
  local sprite = Sprite(spec.w,spec.h,ColorMode.RGB)
  local layer = sprite.layers[1]
  layer.name = spec.id .. " / painted pixels"
  app.transaction(function()
    for i=1,10 do
      if i>1 then sprite:newFrame() end
      local cel = Image(spec.w,spec.h,ColorMode.RGB)
      cel:drawImage(image,Point(-(i-1)*spec.w,0))
      sprite:newCel(layer,i,cel,Point(0,0))
      sprite.frames[i].duration = 0.11
    end
    for _,set in ipairs({
      {"idle",1,2},{"walk",3,6},{"cast",7,8},{"hurt",9,9},{"dead",10,10}
    }) do
      local tag=sprite:newTag(set[2],set[3])
      tag.name=set[1]
    end
  end)
  app.sprite = sprite
  app.command.SaveFileAs{filename=dest .. spec.id .. ".aseprite"}
  src:close()
  sprite:close()
  print("ASEPRITE_OK " .. spec.id)
end
