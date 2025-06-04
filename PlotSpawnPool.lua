local plotSpawns = workspace.PlotSpawns

local PlotSpawnPool = {}

local available = plotSpawns:GetChildren()
local used: {BasePart} = {}

function PlotSpawnPool.Get(player: Player): BasePart
	local plotSpawn = table.remove(available)
	used[player.UserId] = plotSpawn
	return plotSpawn
end

function PlotSpawnPool.Return(player: Player)
	if not used[player.UserId] then 
		return
	end
	
	table.insert(available, used[player.UserId])
	used[player.UserId] = nil
end

return PlotSpawnPool
