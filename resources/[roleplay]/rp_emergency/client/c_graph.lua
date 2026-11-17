--[[
    rp_emergency / c_graph.lua
    Red vial de Los Santos: se reutiliza la de rp_rides (que a su vez la toma de
    rp_citizens) para no duplicar el A*. Estas funciones solo reenvian a sus exports.
]]

function loadRoadGraph() return exports.rp_rides:loadRoadGraph() end
function nearestRoadNode(x, y, ring) return exports.rp_rides:nearestRoadNode(x, y, ring) end
function nodePosition(i) return exports.rp_rides:nodePosition(i) end
function roadNodeAround(x, y, minD, maxD) return exports.rp_rides:roadNodeAround(x, y, minD, maxD) end
function findRoadRoute(a, b, maxExp) return exports.rp_rides:findRoadRoute(a, b, maxExp) end
function routeWaypoints(route) return exports.rp_rides:routeWaypoints(route) end
function laneStartPoint(a, b) return exports.rp_rides:laneStartPoint(a, b) end
