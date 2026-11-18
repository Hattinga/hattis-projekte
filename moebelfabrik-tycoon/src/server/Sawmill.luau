--!strict
-- P05-04: the saw is the first Hocker01 station; the run itself lives in Stations.
local Stations = require(script.Parent.Stations)
local Persistence = require(script.Parent.Persistence)
local Sawmill = {}

export type Result = Stations.Result

function Sawmill.start(controller: Persistence.Controller, now: number, ttlSeconds: number): Result
	return Stations.start(controller, "Saege", now, ttlSeconds)
end

function Sawmill.finish(controller: Persistence.Controller, batchId: string, now: number, ttlSeconds: number): Result
	return Stations.finish(controller, "Saege", batchId, now, ttlSeconds)
end

return table.freeze(Sawmill)
