------------------------------------------------------------------------------
--	GridStatusDirectionArrows by Slaren
------------------------------------------------------------------------------

local GridStatus = Grid:GetModule("GridStatus")

GridStatusDirectionArrows = GridStatus:NewModule("GridStatusDirectionArrows")
GridStatusDirectionArrows.menuName = "Direction arrows"


-- upvalues
local GridRoster = Grid:GetModule("GridRoster")
local GridFrame = Grid:GetModule("GridFrame")
local UnitPosition = UnitPosition
local UnitInRange = UnitInRange
local GetPlayerFacing = GetPlayerFacing
local UnitIsUnit = UnitIsUnit
local GetMouseFocus = GetMouseFocus
local math_atan2 = math.atan2
local math_floor = math.floor
local math_sqrt = math.sqrt
local math_pi = math.pi
local math_2pi = 2*math.pi
local math_hpi = 0.5*math.pi
local format = string.format
local tonumber = tonumber
local rawset = rawset

GridStatusDirectionArrows.defaultDB = {
	debug = false,
	cycle_time = 1 / 20,

	alert_direction = {
		enable = true,
        color = { r = 1, g = 1, b = 1, a = 1, ignore = true },
		priority = 99,
		min_distance = 30,
		always_oor = false,
		filter_units = true,
		filter_target = true,
		filter_mouseover = true,
		filter_focus = true,
	}
}

-- local data
local settings
local settings_direction
local update_frame = CreateFrame("Frame")
local update_timer = 0
local min_distance_sq

local direction_options = {
	["range"] = false,
	-- ["color"] = true,
	["cycle"] = {
		order = 101,
		type = "range",
		name = "Refresh frequency",
		desc = "Number of status refreshes per second\nYou can reduce this number to improve performance",
		width = "full",
		get = function () return 1 / GridStatusDirectionArrows.db.profile.cycle_time end,
		set = function (_, v) GridStatusDirectionArrows.db.profile.cycle_time = 1 / v end,
		min = 1,
		max = 144,
		step = 0.01,
	},
	["mindist"] = {
		order = 102,
		type = "range",
		name = "Minimum distance (yards)",
		desc = "Directions arrows aren't shown on units closer than this",
		width = "full",
		max = 100,
		min = 0,
		step = 0.1,
		get = function () return GridStatusDirectionArrows.db.profile.alert_direction.min_distance end,
		set = function (_, v)
			GridStatusDirectionArrows.db.profile.alert_direction.min_distance = v
			min_distance_sq = v ^ 2
		end,
	},
	["always_oor"] = {
		order = 102.5,
		type = "toggle",
		name = "Always show for units out of range",
		desc = "This option ignores filters",
		width = "full",
		get = function () return GridStatusDirectionArrows.db.profile.alert_direction.always_oor end,
		set = function (_, v) GridStatusDirectionArrows.db.profile.alert_direction.always_oor = v end,
	},
	["filter"] = {
		order = 103,
		type = "toggle",
		name = "Filter units",
		desc = "Enable this to show the direction arrows only in the specified units",
		width = "full",
		get = function () return GridStatusDirectionArrows.db.profile.alert_direction.filter_units end,
		set = function (_, v) GridStatusDirectionArrows.db.profile.alert_direction.filter_units = v end,
	},
	["filters"] = {
		order = 104,
		type = "group",
		name = "Unit filters",
		disabled = function() return not GridStatusDirectionArrows.db.profile.alert_direction.filter_units end,
		inline = true,
		args = {
			["target"] = {
				order = 1,
				type = "toggle",
				name = "Target",
				desc = "Show on target",
				get = function () return GridStatusDirectionArrows.db.profile.alert_direction.filter_target end,
				set = function (_, v) GridStatusDirectionArrows.db.profile.alert_direction.filter_target = v end,
			},
			["mouseover"] = {
				order = 2,
				type = "toggle",
				name = "Mouseover",
				desc = "Show on mouseover",
				get = function () return GridStatusDirectionArrows.db.profile.alert_direction.filter_mouseover end,
				set = function (_, v) GridStatusDirectionArrows.db.profile.alert_direction.filter_mouseover = v end,
			},
			["focus"] = {
				order = 3,
				type = "toggle",
				name = "Focus",
				desc = "Show on focus",
				get = function () return GridStatusDirectionArrows.db.profile.alert_direction.filter_focus end,
				set = function (_, v) GridStatusDirectionArrows.db.profile.alert_direction.filter_focus = v end,
			},
		}
	}
}

function GridStatusDirectionArrows:UpdateSettings()
	settings = self.db.profile
	settings_direction = settings.alert_direction
	min_distance_sq = settings_direction.min_distance ^ 2
end

function GridStatusDirectionArrows:OnInitialize()
	self.super.OnInitialize(self)

	self.db.RegisterCallback(self, "OnProfileChanged", "UpdateSettings")

	self:UpdateSettings()
	
	self:RegisterStatus("alert_direction", "Direction arrows", direction_options, true)
end

function GridStatusDirectionArrows:OnStatusEnable(status)
	if status == "alert_direction" then
		update_frame:SetScript("OnUpdate", function(_, elapsed) return self:OnUpdate(elapsed) end)
	end
end

function GridStatusDirectionArrows:OnStatusDisable(status)
	if status == "alert_direction" then
		self.core:SendStatusLostAllUnits(status)
		update_frame:SetScript("OnUpdate", nil)
	end
end


function GridStatusDirectionArrows:OnUpdate(elapsed)
	update_timer = update_timer + elapsed

	if update_timer >= settings.cycle_time then
		update_timer = 0
		GridStatusDirectionArrows:RefreshAll()
	end
end

local player_x, player_y

function GridStatusDirectionArrows:RefreshMapData()
	-- check player position
	player_x, player_y = UnitPosition("player")

	-- continue only if map supported
	if player_x and player_y then
		return true
	end
	
	return false
end

local function DistanceSq(unit_x, unit_y)
	local x = (unit_x - player_x)
	local y = (unit_y - player_y)

	return x * x + y * y
end

local mousefocusunit

function GridStatusDirectionArrows:IsUnitValid(unitid)
	if UnitIsUnit(unitid, "player") then
		return false
	end
	
	if not settings_direction.filter_units then
		return true
	elseif not settings_direction.filter_mouseover and not settings_direction.filter_target and not settings_direction.filter_focus then
		return true
	end

	if settings_direction.always_oor and not UnitInRange(unitid) then
		return true
	end
	
	-- mouseover
	if settings_direction.filter_mouseover and (UnitIsUnit(unitid, "mouseover") or (mousefocusunit and UnitIsUnit(unitid, mousefocusunit))) then
		return true
	end
	
	-- target
	if settings_direction.filter_target and UnitIsUnit(unitid, "target") then
		return true
	end
	
	-- focus
	if settings_direction.filter_focus and UnitIsUnit(unitid, "focus") then
		return true
	end

	return false
end

-- from TomTom
local function getCoords(column, row)
	local xstart = (column * 56) / 512
	local ystart = (row * 42) / 512
	local xend = ((column + 1) * 56) / 512
	local yend = ((row + 1) * 42) / 512
	local t = {}
	t.left = xstart
	t.top = ystart
	t.right = xend
	t.bottom = yend
	return t
end

local texcoords = setmetatable({}, {__index = function(t, k)
	local col,row = k:match("(%d+):(%d+)")
	col,row = tonumber(col), tonumber(row)
	local obj = getCoords(col, row)
	rawset(t, k, obj)
	return obj
end})

				
function GridStatusDirectionArrows:RefreshAll()
	if not self:RefreshMapData() then
		self.core:SendStatusLostAllUnits("alert_direction")
    else
		local player_facing = GetPlayerFacing()
		
		if settings_direction.filter_units and settings_direction.filter_mouseover then
			local mousefocus = GetMouseFocus()
			if mousefocus and mousefocus.GetAttribute then
				mousefocusunit = mousefocus:GetAttribute("unit")
			else
				mousefocusunit = nil
			end
		end
		
		for guid, unitid in GridRoster:IterateRoster() do
			if not self:IsUnitValid(unitid) then
				self.core:SendStatusLost(guid, "alert_direction")
			else
				local unit_x, unit_y = UnitPosition(unitid)

				if not unit_x or not unit_y then
					self.core:SendStatusLost(guid, "alert_direction")
				else
					local distancesq = DistanceSq(unit_x, unit_y)
					if (min_distance_sq > 0 and distancesq < min_distance_sq) then
						self.core:SendStatusLost(guid, "alert_direction")
					else
						local angle = math_hpi - math_atan2(unit_x - player_x, unit_y - player_y) - player_facing 
						local cell = math_floor(angle / math_2pi * 108 + 0.5) % 108
						local column = cell % 9
						local row = math_floor(cell / 9)
						local key = column .. ":" .. row

						self.core:SendStatusGained(
							guid,
							"alert_direction",
							settings_direction.priority,
							nil,
							settings_direction.color,
							format("%0.1f", math_sqrt(distancesq)),
							1, 
							nil,
							"Interface\\AddOns\\GridStatusDirectionArrows\\Images\\Arrow",
							nil,
							nil,
							nil,
							texcoords[key])
					end
				end
			end
		end
	end
end
