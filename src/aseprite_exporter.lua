-- exports raw data from aseprite. this will then be converted in zig.
-- each image has width*height pixels, from 0 to 4. 0 transparent, and 1-4 colors
-- we then convert this to 2bpp in zig
if #app.sprites ~= 1 then
  return app.alert "You should have at exactly one sprite opened"
end


local sprite = app.sprites[1];
local image_data = "pub const sprites = [_][]u8{"
local bounds_data = "pub const bounds = [_][]u8{"
for cel_index,cel in ipairs(sprite.cels) do
  if cel.layer.name == "Player" then
	image_data = image_data .. "\n\""
	for it in cel.image:pixels() do
      local pixelValue = it() -- get pixel
      image_data = image_data .. pixelValue       -- get pixel x,y coordinates
    end
	image_data = image_data .. "\","
    bounds_data = bounds_data .. "\n\"" .. cel.bounds.x .. " " .. cel.bounds.y .. " " .. cel.bounds.width .. " " .. cel.bounds.height .. "\","
  end
end
image_data = image_data .. "\n};\n"
bounds_data = bounds_data .. "\n};\n"

print(image_data);
print(bounds_data);

filewrite = io.open("c:/Users/user/projects/w4_gamejam/assets/aseprite_import.zig", "w")
filewrite:write(image_data)
filewrite:write(bounds_data)
filewrite:close()	
