local HCIC = CreateFrame("Frame");
local frames = { _ }; --, GeneralDockManager, ChatFrameMenuButton }
local chatFrames = { };
local MouseoverFrames = { };

do -- Polyfills
	if not table.pack then
		function table.pack(...)
		  return { n = select("#", ...), ... }
		end
	end
end

local addonMessageHandlers = {
	["D4"] = {
		["parser"] = function(text)
			return string.split("\t", text)
		end,
		["handlers"] = {
			["PT"] = function (...)
				local timer, lastInstanceMapID, targetName = ...
				HCIC:HandlePullTimer(timer)
			end
		}
	},
	["BigWigs"] = {
		["parser"] = function(text)
			return string.split("^", text) 
		end,
		["handlers"] = {
			["P"] = { -- Plugin communications
				["Pull"] = function (...)
					local timer, sender = ...
					HCIC:HandlePullTimer(timer)
				end,
				["Break"] = function (...)
					local timer, sender = ...
				end
			},
			["V"] = { -- Version communications
			},
			["B"] = { -- Boss communications
			}
		}
	}
};

function HCIC:DispatchAddonMessage(prefix, text, channel, sender)

	-- Recursive resolution until we land on a function
	local messageHandler = addonMessageHandlers[prefix]
	local parser = nil
	
	-- No handler found for this prefix
	if not messageHandler then
		return
	end
	
	-- Parse arguments from the addon message
	local args = table.pack(messageHandler["parser"](text))
	
	-- Load actual handlers
	local resolvedHandler = messageHandler["handlers"]
	
	-- Walk down until we find a function and call it with all remaining arguments
	for i = 1, args.n do
		resolvedHandler = resolvedHandler[args[i]]
	
		if type(resolvedHandler) == "function" then
			DEFAULT_CHAT_FRAME:AddMessage("(" .. prefix .. ") Handling " .. args[i] .. "(" .. string.join(", ", unpack(args, i + 1)) .. ")");
		
			resolvedHandler(unpack(args, i + 1))
			return
		end
		
		if not resolvedHandler then
			return
		end
	end
end

local eventHandlers = {
	["PLAYER_REGEN_ENABLED"] = function (eventFrame)
		HCIC:CombatEnd();
	end,
	-- ["PLAYER_REGEN_DISABLED" = function (eventFrame)
	-- 	HCIC:CombatStart();
	-- end,
	["PLAYER_LOGIN"] = function (eventFrame)
		HCIC:Init();
	end,
	["CHAT_MSG_ADDON"] = function (self, ...)
		local prefix, text, channel, sender = ...
		
		HCIC:DispatchAddonMessage(prefix, text, channel, sender)
	end
};

-- Event handlers
HCIC:SetScript("OnEvent", function(self, event, ...)
	eventHandlers[event](self, ...)
end);

do
	for k, v in pairs(eventHandlers) do
		HCIC:RegisterEvent(k)
	end
end

function HCIC:Init()
	for i = 1, NUM_CHAT_WINDOWS do
		local f = _G["ChatFrame" .. i]
		if (f:IsShown()) then
			local chatMouseover = CreateFrame("Frame", "HCIC" .. i, UIParent)
			chatMouseover:SetPoint("BOTTOMLEFT", "ChatFrame" .. i, "BOTTOMLEFT", -20, -10)
			chatMouseover:SetPoint("TOPRIGHT", "ChatFrame" .. i, "TOPRIGHT", 10, 10)

			chatMouseover.FadeOut = function(self, t)
				HCIC:FadeOut(self, t)
			end
			chatMouseover.FadeIn = function(self, t)
				HCIC:FadeIn(self, t)
			end

			chatMouseover:SetScript("OnEnter", function(self)
				if UnitAffectingCombat("player") or C_PetBattles.IsInBattle() then
					self:FadeIn(self, 0.5)
				end
			end)
			chatMouseover:SetScript("OnLeave", function(self)
				HCIC:ChatOnLeave(self)
			end)

			chatMouseover.Frames = {
				_G["ChatFrame" .. i],
				_G["ChatFrame" .. i .. "Tab"],
				_G["ChatFrame" .. i .. "ButtonFrame"]
			}

			if (i == 1) then
				table.insert(chatMouseover.Frames, GeneralDockManager)
				table.insert(chatMouseover.Frames, GeneralDockManagerScrollFrame)
				if ChatFrameMenuButton:IsShown() then
					table.insert(chatMouseover.Frames, ChatFrameMenuButton)
				end
				table.insert(chatMouseover.Frames, QuickJoinToastButton)
				table.insert(chatMouseover.Frames, ChatFrameChannelButton)
			end

			chatMouseover:SetFrameStrata("BACKGROUND")
			table.insert(MouseoverFrames, _G["HCIC" .. i])
		end
	end
end

function HCIC:CombatStart(t)
	t = tonumber(t or 0)
	for _, f in pairs(MouseoverFrames) do
		f:FadeOut(t)
	end
end

function HCIC:CombatEnd(t)
	t = tonumber(t or 0)

	for _, f in pairs(MouseoverFrames) do
		f:FadeIn(t)
	end
end

function HCIC:HandlePullTimer(t)
	t = tonumber(t or 0);

	for _, f in pairs(MouseoverFrames) do
		f:FadeOut(t)
	end
end

local function fade(self, mode, t)
	for _, frame in pairs(self.Frames) do
		local alpha = frame:GetAlpha()
		
		if mode == 0 then
			-- Fade in
			
			-- Restore the standard Show() function by using ours.
			frame.Show = Show
			frame:Show()
			
			-- Fade in
			UIFrameFadeIn(frame, t * (1 - alpha), alpha, 1)
		else
			-- Fade out
			UIFrameFadeOut(frame, t * alpha, alpha, 0)
			
			-- NOP out the standard Show() function
			frame.Show = function () end
			frame.fadeInfo.finishedArg1 = frame
			frame.fadeInfo.finishedFunc = frame.Hide
			
			-- Schedule a combat state check right after the pull. Avoids issues with cancelled pulls.
			-- We add a small delta in case of late pullswith regards to the pull timer.
			C_Timer.After(t + 0.5, function()
				if not UnitAffectingCombat("player") then
					-- Fade back in 5 times faster
					HCIC:FadeIn(self, t / 5.0)
				end
			end)
		end
	end
end

function HCIC:FadeOut(self, t)
	fade(self, 1, t)
end

function HCIC:FadeIn(self, t)
	fade(self, 0, t)
end


-- Called when the cursor leaves a chat window.
function HCIC:ChatOnLeave(self)
	local f = GetMouseFocus()
	if f then
		if f.messageInfo then
			return
		end
		if HCIC:IsInArray(self.Frames, f) then
			return
		end
		if f:GetParent() then
			f = f:GetParent()
			if HCIC:IsInArray(self.Frames, f) then
				return
			end
			if f:GetParent() then
				f = f:GetParent()
				if HCIC:IsInArray(self.Frames, f) then
					return
				end
			end
		end
	end

	-- In combat, not hovering anything important, disappear again.
	if UnitAffectingCombat("player") then
		self:FadeOut(0.5)
	end
end

WorldFrame:HookScript(
	"OnEnter",
	function()
		if UnitAffectingCombat("player") then
			HCIC:CombatStart()
		end
	end
)

function HCIC:IsInArray(array, s)
	for _, v in pairs(array) do
		if (v == s) then
			return true;
		end
	end
	
	return false;
end

hooksecurefunc("FCF_Tab_OnClick", function(self)
	chatFrame = _G["ChatFrame" .. self:GetID()]
	if chatFrame.isDocked then
		HCIC1.Frames[1] = chatFrame
	end
end);
