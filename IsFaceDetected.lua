local nms = dofile 'nms.lua'

function IsFaceDetected(im,boxes,scores,thresh,cl_names)
  local ok = pcall(require,'qt')
  if not ok then
    error('You need to run visualize_detections using qlua')
  end
  require 'qttorch'
  require 'qtwidget'
  local face_detected = 0

  -- select best scoring boxes without background
  local max_score,idx = scores[{{},{2,-1}}]:max(2)

  local idx_thresh = max_score:gt(thresh)
  max_score = max_score[idx_thresh]
  idx = idx[idx_thresh]

  local r = torch.range(1,boxes:size(1)):long()
  local rr = r[idx_thresh]
  if rr:numel() == 0 then
--    error('No detections with a score greater than the specified threshold')
	return 0
  end

  local boxes_thresh = boxes:index(1,rr)
  
  local keep = nms(torch.cat(boxes_thresh:float(),max_score:float(),2),0.3)
  
  boxes_thresh = boxes_thresh:index(1,keep)
  max_score = max_score:index(1,keep)
  idx = idx:index(1,keep)

  local num_boxes = boxes_thresh:size(1)
  local widths  = boxes_thresh[{{},3}] - boxes_thresh[{{},1}]
  local heights = boxes_thresh[{{},4}] - boxes_thresh[{{},2}]
  for i=1,num_boxes do
    
	  if idx[i] == 15 then
		  face_detected = 1 -- as long as a face is deteced, this generated image pass our test. TODO: other detection outcome shouldn't happen. Construct a probabilistic test
	  end
  end
  return face_detected
end

