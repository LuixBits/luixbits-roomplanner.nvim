local M = {}

function M.normalize(a, b)
  if a <= b then
    return a, b
  end
  return b, a
end

function M.new(a, b)
  local start_value, finish_value = M.normalize(a, b)
  return { start = start_value, finish = finish_value }
end

function M.length(a, b)
  local start_value, finish_value = M.normalize(a, b)
  return finish_value - start_value
end

-- Positive-length overlap. Endpoint contact deliberately returns false.
function M.overlaps_positive(a0, a1, b0, b1)
  a0, a1 = M.normalize(a0, a1)
  b0, b1 = M.normalize(b0, b1)
  return math.max(a0, b0) < math.min(a1, b1)
end

function M.overlap_length(a0, a1, b0, b1)
  a0, a1 = M.normalize(a0, a1)
  b0, b1 = M.normalize(b0, b1)
  return math.max(0, math.min(a1, b1) - math.max(a0, b0))
end

-- Closed intersection. Endpoint contact returns true.
function M.intersects_closed(a0, a1, b0, b1)
  a0, a1 = M.normalize(a0, a1)
  b0, b1 = M.normalize(b0, b1)
  return math.max(a0, b0) <= math.min(a1, b1)
end

function M.contains_closed(a0, a1, value)
  a0, a1 = M.normalize(a0, a1)
  return value >= a0 and value <= a1
end

function M.contains_half_open(a0, a1, value)
  a0, a1 = M.normalize(a0, a1)
  return value >= a0 and value < a1
end

function M.contains_interval(a0, a1, b0, b1)
  a0, a1 = M.normalize(a0, a1)
  b0, b1 = M.normalize(b0, b1)
  return b0 >= a0 and b1 <= a1
end

function M.intersection(a0, a1, b0, b1, include_contact)
  a0, a1 = M.normalize(a0, a1)
  b0, b1 = M.normalize(b0, b1)
  local start_value = math.max(a0, b0)
  local finish_value = math.min(a1, b1)
  if start_value < finish_value or (include_contact and start_value == finish_value) then
    return start_value, finish_value
  end
  return nil
end

function M.distance_to_point(a0, a1, value)
  a0, a1 = M.normalize(a0, a1)
  if value < a0 then
    return a0 - value
  elseif value > a1 then
    return value - a1
  end
  return 0
end

-- Subtract positive-length cuts and return ordered closed-boundary pieces.
-- Endpoint-only cuts have no effect.
function M.subtract(a0, a1, cuts)
  a0, a1 = M.normalize(a0, a1)
  local normalized = {}
  local i
  for i = 1, #(cuts or {}) do
    local cut = cuts[i]
    local c0 = cut.start or cut[1]
    local c1 = cut.finish or cut[2]
    c0, c1 = M.normalize(c0, c1)
    c0 = math.max(a0, c0)
    c1 = math.min(a1, c1)
    if c0 < c1 then
      normalized[#normalized + 1] = { c0, c1 }
    end
  end
  table.sort(normalized, function(left, right)
    if left[1] ~= right[1] then
      return left[1] < right[1]
    end
    return left[2] < right[2]
  end)

  local merged = {}
  for i = 1, #normalized do
    local cut = normalized[i]
    local last = merged[#merged]
    if last and cut[1] <= last[2] then
      last[2] = math.max(last[2], cut[2])
    else
      merged[#merged + 1] = { cut[1], cut[2] }
    end
  end

  local pieces = {}
  local cursor = a0
  for i = 1, #merged do
    local cut = merged[i]
    if cursor < cut[1] then
      pieces[#pieces + 1] = { start = cursor, finish = cut[1] }
    end
    cursor = math.max(cursor, cut[2])
  end
  if cursor < a1 then
    pieces[#pieces + 1] = { start = cursor, finish = a1 }
  end
  return pieces
end

M.positive_overlap = M.overlaps_positive
M.closed_overlap = M.intersects_closed
M.contains = M.contains_closed

return M
