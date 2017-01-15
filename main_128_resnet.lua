require 'torch'
require 'nn'
require 'optim'
require 'nnf'
require 'image'
require 'cudnn'
require 'inn'
-- resnet

local ReLU = cudnn.ReLU
local SBatchNorm = nn.SpatialBatchNormalization
local Convolution = cudnn.SpatialConvolution
local shortcutType = 'B'

	local function layer(block, features, count, stride)
      local s = nn.Sequential()
      for i=1,count do
         s:add(block(features, i == 1 and stride or 1))
      end
      return s
   end
   -- The shortcut layer is either identity or 1x1 convolution
   local function shortcut(nInputPlane, nOutputPlane, stride)
      local useConv = shortcutType == 'C' or
         (shortcutType == 'B' and nInputPlane ~= nOutputPlane)
      if useConv then
         -- 1x1 convolution
         return nn.Sequential()
            :add(Convolution(nInputPlane, nOutputPlane, 1, 1, stride, stride))
            :add(SBatchNorm(nOutputPlane))
      elseif nInputPlane ~= nOutputPlane then
         -- Strided, zero-padded identity shortcut
         return nn.Sequential()
            :add(nn.SpatialAveragePooling(1, 1, stride, stride))
            :add(nn.Concat(2)
               :add(nn.Identity())
               :add(nn.MulConstant(0)))
      else
         return nn.Identity()
      end
   end
   local function basicblock(n, stride)
	   print(n)
 --     local nInputPlane = iChannels
 --     iChannels = n
 nInputPlane = n -- I don't use block for down/up sample
      local s = nn.Sequential()
      s:add(Convolution(nInputPlane,n,3,3,stride,stride,1,1))
      s:add(SBatchNorm(n))

      return nn.Sequential()
         :add(nn.ConcatTable()
            :add(s)
            :add(shortcut(nInputPlane, n, stride)))
         :add(nn.CAddTable(true))
         :add(ReLU(true))
   end
----------------------------------------------------------------
-- fast RCNN
--TODO: replace with state-of-the-art face detector
params = torch.load('obj_det/cachedir/frcnn_alexnet.t7')
loadModel = dofile 'obj_det/models/frcnn_alexnet.lua'
model = loadModel(params)
model:add(nn.SoftMax())
model:evaluate()
model:cuda()
image_transformer= nnf.ImageTransformer{mean_pix={102.9801,115.9465,122.7717}, raw_scale = 255, swap = {3,2,1}}
feat_provider = nnf.FRCNN{image_transformer=image_transformer}
feat_provider:evaluate() -- testing mode
detector = nnf.ImageDetect(model, feat_provider)
dofile 'IsFaceDetected.lua'
threshold = 0.01
cls = {'aeroplane','bicycle','bird','boat','bottle','bus','car',
       'cat','chair','cow','diningtable','dog','horse','motorbike',
       'person','pottedplant','sheep','sofa','train','tvmonitor'}

print('fast RCNN initialized')
-- DCGAN
util = paths.dofile('util.lua')
opt = {
   dataset = 'lsun',       -- imagenet / lsun / folder
   batchSize = 36,
   loadSize = 192,
   fineSize = 128,
   nz = 100,               -- #  of dim for Z
   ngf = 128,               -- #  of gen filters in first conv layer
   ndf = 128,               -- #  of discrim filters in first conv layer
   nThreads = 4,           -- #  of data loading threads to use
   niter = 25,             -- #  of iter at starting learning rate
   lr = 0.001,            -- initial learning rate for adam
   beta1 = 0.9,            -- momentum term of adam
   ntrain = math.huge,     -- #  of examples per epoch. math.huge for full dataset
   display = 1,            -- display samples while training. 0 = false
   display_id = 10,        -- display window id.
   gpu = 1,                -- gpu = 0 is CPU mode. gpu=X is GPU mode on GPU X
   name = 'experiment1',
   noise = 'normal',       -- uniform / normal
}

-- one-line argument parser. parses enviroment variables to override the defaults
for k,v in pairs(opt) do opt[k] = tonumber(os.getenv(k)) or os.getenv(k) or opt[k] end
print(opt)
if opt.display == 0 then opt.display = false end

opt.manualSeed = torch.random(1, 10000) -- fix seed
print("Random Seed: " .. opt.manualSeed)
torch.manualSeed(opt.manualSeed)
torch.setnumthreads(1)
torch.setdefaulttensortype('torch.FloatTensor')

-- create data loader
local DataLoader = paths.dofile('data/data.lua')
local data = DataLoader.new(opt.nThreads, opt.dataset, opt)
print("Dataset: " .. opt.dataset, " Size: ", data:size())
----------------------------------------------------------------------------
local function weights_init(m)
   local name = torch.type(m)
   if name:find('Convolution') then
      m.weight:normal(0.0, 0.02)
      m.bias:fill(0)
   elseif name:find('BatchNormalization') then
      if m.weight then m.weight:normal(1.0, 0.02) end
      if m.bias then m.bias:fill(0) end
   end
end

local nc = 3
local nz = opt.nz
local ndf = opt.ndf
local ngf = opt.ngf
local real_label = 1
local fake_label = 0

local SpatialBatchNormalization = nn.SpatialBatchNormalization
local SpatialConvolution = nn.SpatialConvolution
local SpatialFullConvolution = nn.SpatialFullConvolution

local netG = nn.Sequential()
-- input is Z, going into a convolution
netG:add(SpatialFullConvolution(nz, ngf * 16, 4, 4))
netG:add(SpatialBatchNormalization(ngf * 16)):add(nn.ReLU(true))
netG:add(layer(basicblock, ngf * 16, 1)) 
-- state size: (ngf*8) x 4 x 4
netG:add(SpatialFullConvolution(ngf * 16, ngf * 8, 4, 4, 2, 2, 1, 1))
netG:add(SpatialBatchNormalization(ngf * 8)):add(nn.ReLU(true))
netG:add(layer(basicblock, ngf * 8, 1))   
-- state size: (ngf*4) x 8 x 8
netG:add(SpatialFullConvolution(ngf * 8, ngf * 4, 4, 4, 2, 2, 1, 1))
netG:add(SpatialBatchNormalization(ngf * 4)):add(nn.ReLU(true))
netG:add(layer(basicblock, ngf * 4, 1))   
-- state size: (ngf*2) x 16 x 16
netG:add(SpatialFullConvolution(ngf * 4, ngf * 2, 4, 4, 2, 2, 1, 1))
netG:add(SpatialBatchNormalization(ngf)):add(nn.ReLU(true))
netG:add(layer(basicblock, ngf * 2, 1))   
-- state size: (ngf) x 32 x 32
netG:add(SpatialFullConvolution(ngf * 2, ngf, 4, 4, 2, 2, 1, 1))
netG:add(SpatialBatchNormalization(ngf)):add(nn.ReLU(true))
netG:add(layer(basicblock, ngf, 1))   
-- state size: (nc) x 64 x 64
netG:add(SpatialFullConvolution(ngf, nc, 4, 4, 2, 2, 1, 1))
netG:add(nn.Tanh())
-- state size: (nc) x 128 x 128
netG:apply(weights_init)

local netD = nn.Sequential()

-- input is (nc) x 128 x 128
netD:add(SpatialConvolution(nc, ndf, 4, 4, 2, 2, 1, 1))
netD:add(nn.LeakyReLU(0.2, true))
netD:add(layer(basicblock, ndf, 1)) 
-- state size: (ndf) x 64 x 64
netD:add(SpatialConvolution(ndf, ndf * 2, 4, 4, 2, 2, 1, 1))
netD:add(SpatialBatchNormalization(ndf * 2)):add(nn.LeakyReLU(0.2, true))
netD:add(layer(basicblock, ndf * 2, 1)) 
-- state size: (ndf) x 32 x 32
netD:add(SpatialConvolution(ndf*2, ndf * 4, 4, 4, 2, 2, 1, 1))
netD:add(SpatialBatchNormalization(ndf * 4)):add(nn.LeakyReLU(0.2, true))
netD:add(layer(basicblock, ndf * 4, 1)) 
-- state size: (ndf*2) x 16 x 16
netD:add(SpatialConvolution(ndf * 4, ndf * 8, 4, 4, 2, 2, 1, 1))
netD:add(SpatialBatchNormalization(ndf * 8)):add(nn.LeakyReLU(0.2, true))
netD:add(layer(basicblock, ndf * 8, 1)) 
-- state size: (ndf*4) x 8 x 8
netD:add(SpatialConvolution(ndf * 8, ndf * 16, 4, 4, 2, 2, 1, 1))
netD:add(SpatialBatchNormalization(ndf * 16)):add(nn.LeakyReLU(0.2, true))
netD:add(layer(basicblock, ndf * 16, 1)) 
-- state size: (ndf*8) x 4 x 4
netD:add(SpatialConvolution(ndf * 16, 1, 4, 4))
netD:add(nn.Sigmoid())
-- state size: 1 x 1 x 1
netD:add(nn.View(1):setNumInputDims(3))
-- state size: 1

netD:apply(weights_init)

local criterion = nn.BCECriterion()
---------------------------------------------------------------------------
optimStateG = {
   learningRate = opt.lr,
   beta1 = opt.beta1,
}
optimStateD = {
   learningRate = opt.lr,
   beta1 = opt.beta1,
}
----------------------------------------------------------------------------
local input = torch.Tensor(opt.batchSize, 3, opt.fineSize, opt.fineSize)
local noise = torch.Tensor(opt.batchSize, nz, 1, 1)
local label = torch.Tensor(opt.batchSize)
local errD, errG
local epoch_tm = torch.Timer()
local tm = torch.Timer()
local data_tm = torch.Timer()
----------------------------------------------------------------------------
if opt.gpu > 0 then
   require 'cunn'
   cutorch.setDevice(opt.gpu)
   input = input:cuda();  noise = noise:cuda();  label = label:cuda()
   netG = util.cudnn(netG);     netD = util.cudnn(netD)
   netD:cuda();           netG:cuda();           criterion:cuda()
end

local parametersD, gradParametersD = netD:getParameters()
local parametersG, gradParametersG = netG:getParameters()

if opt.display then disp = require 'display' end

noise_vis = noise:clone()
if opt.noise == 'uniform' then
    noise_vis:uniform(-1, 1)
elseif opt.noise == 'normal' then
    noise_vis:normal(0, 1)
end

-- create closure to evaluate f(X) and df/dX of discriminator
local fDx = function(x)
   netD:apply(function(m) if torch.type(m):find('Convolution') then m.bias:zero() end end)
   netG:apply(function(m) if torch.type(m):find('Convolution') then m.bias:zero() end end)

   gradParametersD:zero()
   -- train with real
   data_tm:reset(); data_tm:resume()
   local real = data:getBatch()
   data_tm:stop()
   input:copy(real)
--   print(input:nDimension()) --->4
--   print(input:size()) ---> 64,3,64,64
   label:fill(real_label)

   local output = netD:forward(input)
   local errD_real = criterion:forward(output, label)
   local df_do = criterion:backward(output, label)
   netD:backward(input, df_do)

   -- train with fake
   if opt.noise == 'uniform' then -- regenerate random noise
       noise:uniform(-1, 1)
   elseif opt.noise == 'normal' then
       noise:normal(0, 1)
   end
   local fake = netG:forward(noise)
   input:copy(fake)
--   print('#input=', #input) -> 64, 3, 64, 64
   label:fill(fake_label)
   Global_Var = os.clock()
--   g_im_gen = image.lena()
--   g_im_gen = input:select(1,1):clone():float() -- select the 1st image
   IsFace = torch.Tensor(opt.batchSize,1)
   for i=1,opt.batchSize do
		g_im_gen = input:select(1,i):clone():float() -- select the ith image		
--   print(input:nDimension()) 
--   print(input:size()) 
--   print(g_im_gen:nDimension()) 
--   print(g_im_gen:size()) 
	   torch.manualSeed(500) -- fix seed for reproducibility
	   bboxes = torch.Tensor(100,4)
	   bboxes:select(2,1):random(1,g_im_gen:size(3)/2)
	   bboxes:select(2,2):random(1,g_im_gen:size(2)/2)
	   bboxes:select(2,3):random(g_im_gen:size(3)/2+1,g_im_gen:size(3))
	   bboxes:select(2,4):random(g_im_gen:size(2)/2+1,g_im_gen:size(2))
	   scores, bboxes = detector:detect(g_im_gen, bboxes)
	   IsFace[i] = IsFaceDetected(g_im_gen,bboxes,scores,threshold,cls)
   end
   local output = netD:forward(input) --use G's result as input of D
   local errD_fake = criterion:forward(output, label) -- want D(G(x)), the prob of x coming from real data, to be 0 
   local df_do = criterion:backward(output, label)
   netD:backward(input, df_do)
	print ('errD_real:', errD_real, 'errD_fake:', errD_fake)
   errD = errD_real + errD_fake

   return errD, gradParametersD
end

-- create closure to evaluate f(X) and df/dX of generator
local fGx = function(x)
   netD:apply(function(m) if torch.type(m):find('Convolution') then m.bias:zero() end end)
   netG:apply(function(m) if torch.type(m):find('Convolution') then m.bias:zero() end end)

   gradParametersG:zero()

   --[[ the three lines below were already executed in fDx, so save computation
   noise:uniform(-1, 1) -- regenerate random noise
   local fake = netG:forward(noise)
   input:copy(fake) ]]--
   label:fill(real_label) -- fake labels are real for generator cost

   local output = netD.output -- netD:forward(input) was already executed in fDx, so save computation
--   print('I am printing a global var:',Global_Var)
   print(IsFace:sum(), ' faces detected out of 16 images')
--   print('size of IsFace', #IsFace)
--   print('size of output', #output)
   output = output:double() -- convert to float in order to do map:
   IsFace = IsFace:double()
--   print(IsFace)
--   print('output', output)
   output:map(IsFace, function(xx, yy) return yy*0.5+xx*0.5 end) -- fuse the two detection results with equal weights  
   output = output:cuda() -- convert back
   errG = criterion:forward(output, label) -- log(1-D(G(z)))
   local df_do = criterion:backward(output, label)
   local df_dg = netD:updateGradInput(input, df_do)

   netG:backward(noise, df_dg)
   return errG, gradParametersG
end


-- train
for epoch = 1, opt.niter do
   epoch_tm:reset()
   -- decrease rate
--[[   optimStateG.learningRate = opt.lr/epoch
   optimStateG.beta1 = opt.beta1/epoch
   optimStateD.learningRate = opt.lr/epoch
   optimStateD.beta1 = opt.beta1/epoch
--]]
   local counter = 0
   for i = 1, math.min(data:size(), opt.ntrain), opt.batchSize do
      tm:reset()
      -- (1) Update D network: maximize log(D(x)) + log(1 - D(G(z)))
      optim.adam(fDx, parametersD, optimStateD)

      -- (2) Update G network: maximize log(D(G(z)))
      optim.adam(fGx, parametersG, optimStateG)

      -- display
      counter = counter + 1
      if counter % 10 == 0 and opt.display then
          local fake = netG:forward(noise_vis)
          local real = data:getBatch()
          disp.image(fake, {win=opt.display_id, title=opt.name})
          disp.image(real, {win=opt.display_id * 3, title=opt.name})
      end

      -- logging
      if ((i-1) / opt.batchSize) % 1 == 0 then
         print(('Epoch: [%d][%8d / %8d]\t Time: %.3f  DataTime: %.3f  '
                   .. '  Err_G: %.4f  Err_D: %.4f'):format(
                 epoch, ((i-1) / opt.batchSize),
                 math.floor(math.min(data:size(), opt.ntrain) / opt.batchSize),
                 tm:time().real, data_tm:time().real,
                 errG and errG or -1, errD and errD or -1))
      end
   end
   paths.mkdir('checkpoints')
   util.save('checkpoints/' .. opt.name .. '_' .. epoch .. '_net_G.t7', netG, opt.gpu)
   util.save('checkpoints/' .. opt.name .. '_' .. epoch .. '_net_D.t7', netD, opt.gpu)
   print(('End of epoch %d / %d \t Time Taken: %.3f'):format(
            epoch, opt.niter, epoch_tm:time().real))
end