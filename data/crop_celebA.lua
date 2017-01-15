require 'torch'
require 'image'

local data = os.getenv('DATA_ROOT') .. '/img_align_celeba'
local i=1
for f in paths.files(data, function(nm) return nm:find('.jpg') end) do
    local f2 = paths.concat(data, f)
    local im = image.load(f2)
    local x1, y1 = 30, 40
    local cropped = image.crop(im, x1, y1, x1 + 138, y1 + 138)
    local scaled = image.scale(cropped, 128, 128)
	print(i, f2, #scaled)
    image.save(f2, scaled)
	i = i+1
end
