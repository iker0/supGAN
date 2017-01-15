require 'torch'
require 'image'

local data = os.getenv('DATA_ROOT')
for f in paths.files(data, function(nm) return nm:find('.jpg') end) do
    local fin = paths.concat(data, f)
--	local fout_path = paths.concat(data, '/crop')
	local fout_path = data .. "/crop"
--	print (fout_path)
 	local im = image.load(fin)
	for y1 = 100, 240, 20 do
		for x1 = 1, 60, 20 do
--    local x1, y1 = 1, 170
		 local fout = paths.concat(fout_path, x1 .. "_" .. y1 .. f)
	   	 local cropped = image.crop(im, x1, y1, x1 + 320, y1 + 320)
   		 local scaled = image.scale(cropped, 64, 64)
	   	 image.save(fout, scaled)
		end
	end
end
