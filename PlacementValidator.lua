local PlacementValidator = {}

function PlacementValidator.WithinBounds(plot: Model, objectSize: Vector3, worldCF: CFrame)
	local plotCF, plotSize = plot:GetBoundingBox()
	local objectCF = plotCF:ToObjectSpace(worldCF)
	
	local cornerPoints = {}
	for _, x in {-1, 1} do
		for _, z in {-1, 1} do
			table.insert(cornerPoints, objectCF:PointToWorldSpace(
				Vector3.new(x * objectSize.X / 2, 0, z * objectSize.Z / 2)	
			))
		end
	end
	
	for _, corner in cornerPoints do
		if math.abs(corner.X) > plotSize.X / 2 or math.abs(corner.Z) > plotSize.Z / 2 then
			return false
		end
	end
	
	return true 
end

function PlacementValidator.NotIntersectingObjects(plot: Model, objectSize: Vector3, worldCF: CFrame)
	local params = OverlapParams.new()
	params:AddToFilter(plot.Objects)
	params.FilterType = Enum.RaycastFilterType.Include
	local parts = workspace:GetPartBoundsInBox(worldCF, objectSize, params)
	return #parts == 0
end

return PlacementValidator
