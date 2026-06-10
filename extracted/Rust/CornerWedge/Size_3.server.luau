mesh = script.Parent.Mesh
brick = script.Parent

function changeSize(property)
	if property ~= "Size" then return end
	mesh.Scale = Vector3.new(brick.Size.x * 2, brick.Size.y * 2, brick.Size.z * 2)
end

brick.Changed:connect(changeSize)

changeSize("Size")