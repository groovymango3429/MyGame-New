local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlotManager = require(script.Parent.PlotManager)
local PlotStorage = require(script.Parent.PlotStorage)
local GetPlot = ReplicatedStorage.Events.GetPlot
local TryPlace = ReplicatedStorage.Events.TryPlace
local TryDelete = ReplicatedStorage.Events.TryDelete

Players.PlayerAdded:Connect(PlotStorage.Load)
Players.PlayerRemoving:Connect(PlotStorage.Save)
game:BindToClose(PlotStorage.WaitForSave)

GetPlot.OnServerInvoke = PlotManager.GetPlot
TryPlace.OnServerInvoke = PlotManager.Place
TryDelete.OnServerInvoke = PlotManager.Delete