--[[
	Usage so far:  MonDKP.Sync:SendData(prefix, core.WorkingTable)  --sends table through comm channel for updates

	Prefix's used: 	MonDKPDataSync - Syncs entire DKP log
					MonDKPBroadcast - Message on broadcast
					MonDKPLogSync - Syncs entire Loot Log
					MonDKPNotify - string of variables to be broken down to launch modules (eg. timer 20 timer_title_string)
					MonDKPLootAward - individual loot awards (primarily when someone wins a bid, broadcasts that single win to loot table)


--]]	

local _, core = ...;
local _G = _G;
local MonDKP = core.MonDKP;

MonDKP.Sync = LibStub("AceAddon-3.0"):NewAddon("MonDKP", "AceComm-3.0")

local LibAceSerializer = LibStub:GetLibrary("AceSerializer-3.0")
local LibCompress = LibStub:GetLibrary("LibCompress")
local LibCompressAddonEncodeTable = LibCompress:GetAddonEncodeTable()

local function ValidateSender(sender)								-- returns true if "sender" has permission to write officer notes. false if not or not found.
	local rankIndex = MonDKP:GetGuildRankIndex(sender);				-- validates user has permission to push table update broadcasts.
	
	if rankIndex then
		return C_GuildInfo.GuildControlGetRankFlags(rankIndex)[12]
	else
		return false;
	end
end

-------------------------------------------------
-- Register Broadcast Prefixs
-------------------------------------------------

function MonDKP.Sync:OnEnable()
	MonDKP.Sync:RegisterComm("MonDKPDataSync", MonDKP.Sync:OnCommReceived())		-- broadcasts entire DKP table
	MonDKP.Sync:RegisterComm("MonDKPBroadcast", MonDKP.Sync:OnCommReceived())		-- broadcasts a message that is printed as is
	MonDKP.Sync:RegisterComm("MonDKPNotify", MonDKP.Sync:OnCommReceived())			-- broadcasts a command (ex. timers, bid timers, stop all timers etc.)
	MonDKP.Sync:RegisterComm("MonDKPLogSync", MonDKP.Sync:OnCommReceived())			-- broadcasts entire loot table
	MonDKP.Sync:RegisterComm("MonDKPLootAward", MonDKP.Sync:OnCommReceived())		-- broadcasts individual loot award to loot table
	MonDKP.Sync:RegisterComm("MonDKPDeleteLoot", MonDKP.Sync:OnCommReceived())		-- broadcasts deleted loot award entries
	MonDKP.Sync:RegisterComm("MonDKPDKPLogSync", MonDKP.Sync:OnCommReceived())		-- broadcasts entire DKP history table
	MonDKP.Sync:RegisterComm("MonDKPDKPAward", MonDKP.Sync:OnCommReceived())		-- broadcasts individual DKP award to DKP history table
end

function MonDKP.Sync:OnCommReceived(prefix, message, distribution, sender)
	if (prefix) then
		if ValidateSender(sender) then
			if (prefix == "MonDKPBroadcast") and sender ~= UnitName("player") then
				MonDKP:Print(message)
			elseif (prefix == "MonDKPNotify") then
				local command, arg1, arg2, arg3 = strsplit(",", message);
				if sender ~= UnitName("player") then
					if command == "StartTimer" then
						MonDKP:StartTimer(arg1, arg2)
					elseif command == "StartBidTimer" then
						MonDKP:StartBidTimer(arg1, arg2, arg3)
					elseif command == "StopBidTimer" then
						if MonDKP.BidTimer then
							MonDKP.BidTimer:SetScript("OnUpdate", nil)
							MonDKP.BidTimer:Hide()
						end
					end
				end
			end
			if (sender ~= UnitName("player")) then
				if (prefix == "MonDKPDataSync" or prefix == "MonDKPLogSync" or prefix == "MonDKPLootAward" or prefix == "MonDKPDKPLogSync" or prefix == "MonDKPDKPAward" or prefix == "MonDKPDeleteLoot") then
					if (prefix == "MonDKPDataSync") then
						MonDKP:Print("DKP database updated by "..sender.."...")
					end
					decoded = LibCompress:Decompress(LibCompressAddonEncodeTable:Decode(message))
					local success, deserialized = LibAceSerializer:Deserialize(decoded);
					if success then
						if (prefix == "MonDKPLogSync") then
							MonDKP_Loot = deserialized;
							MonDKP:LootHistory_Reset()
							MonDKP:LootHistory_Update("No Filter")
							MonDKP:Print("Loot history update complete.")
						elseif prefix == "MonDKPLootAward" then
							tinsert(MonDKP_Loot, deserialized)
							MonDKP:LootHistory_Reset()
							MonDKP:LootHistory_Update("No Filter")
						elseif prefix == "MonDKPDKPAward" then
							tinsert(MonDKP_DKPHistory, deserialized)
							MonDKP:DKPHistory_Reset()
	      					MonDKP:DKPHistory_Update()
						elseif prefix == "MonDKPDKPLogSync" then
							MonDKP_DKPHistory = deserialized
							MonDKP:DKPHistory_Reset()
	      					MonDKP:DKPHistory_Update()
							MonDKP:Print("DKP history update complete.")
						elseif prefix == "MonDKPDeleteLoot" then
							table.remove(MonDKP_Loot, deserialized)
							MonDKP:LootHistory_Reset()
							MonDKP:SortLootTable()
							MonDKP:LootHistory_Update("No Filter");						
						else
							MonDKP_DKPTable = deserialized;			-- commits to SavedVariables
							MonDKP:FilterDKPTable(core.currentSort, "reset")
						end
					else
						print(deserialized)  -- error reporting if string doesn't get deserialized correctly
					end
				end
			end
			if (sender == UnitName("player") and prefix == "MonDKPLogSync") then
				MonDKP:Print("Loot History Broadcast Complete")
			end
			if (sender == UnitName("player") and prefix == "MonDKPDKPLogSync") then
				MonDKP:Print("DKP History Broadcast Complete")
			end
		else
			if core.IsOfficer then
				local msg = sender..", has attempted to broadcast with \""..prefix.."\" prefix."
				MonDKP:Print(msg)
				StaticPopupDialogs["MODIFY_WARNING"] = {
				text = msg,
				button1 = "Ok",
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = 3,
			}
			StaticPopup_Show ("MODIFY_WARNING")
			end
		end
	end
end

function MonDKP.Sync:SendData(prefix, data)
	local serialized = nil;
	local packet = nil;
	local verInteg1 = false;
	local verInteg2 = false;

	if (prefix == "MonDKPNotify") then
		MonDKP.Sync:SendCommMessage(prefix, data, "RAID")
		return;
	end

	if (prefix == "MonDKPBroadcast") then
		MonDKP.Sync:SendCommMessage(prefix, data, "GUILD")
		return;
	end

	if data then
		serialized = LibAceSerializer:Serialize(data);
	end

	-- compress serialized string with both possible compressions for comparison
	-- I do both in case one of them doesn't retain integrity after decompression and decoding, the other is sent
	local huffmanCompressed = LibCompress:CompressHuffman(serialized);
	if huffmanCompressed then
		huffmanCompressed = LibCompressAddonEncodeTable:Encode(huffmanCompressed);
	end
	local lzwCompressed = LibCompress:CompressLZW(serialized);
	if lzwCompressed then
		lzwCompressed = LibCompressAddonEncodeTable:Encode(lzwCompressed);
	end

	-- Decode to test integrity
	local test1 = LibCompress:Decompress(LibCompressAddonEncodeTable:Decode(huffmanCompressed))
	if test1 == serialized then
		verInteg1 = true
	end
	local test2 = LibCompress:Decompress(LibCompressAddonEncodeTable:Decode(lzwCompressed))
	if test2 == serialized then
		verInteg2 = true
	end
	-- check which string with verified integrity is shortest. Huffman usually is
	if (strlen(huffmanCompressed) < strlen(lzwCompressed) and verInteg1 == true) then
		packet = huffmanCompressed;
	elseif (strlen(huffmanCompressed) > strlen(lzwCompressed) and verInteg2 == true) then
		packet = lzwCompressed
	elseif (strlen(huffmanCompressed) == strlen(lzwCompressed)) then
		if verInteg1 == true then packet = huffmanCompressed
		elseif verInteg2 == true then packet = lzwCompressed end
	end

	--debug lengths, uncomment to see string lengths of each uncompressed, Huffman and LZQ compressions
	--[[print("Uncompressed: ", strlen(serialized))
	print("Huffman: ", strlen(huffmanCompressed))
	print("LZQ: ", strlen(lzwCompressed)) --]]

	-- send packet
	if prefix == "MonDKPNotify" then
		MonDKP.Sync:SendCommMessage(prefix, packet, "RAID")					-- broadcasts timers to raid, all else goes to guild
	else
		MonDKP.Sync:SendCommMessage(prefix, packet, "GUILD")
	end

	-- Verify Send
	if (prefix == "MonDKPDataSync") then
		MonDKP:Print("DKP Database Broadcasted")
	elseif (prefix == "MonDKPLogSync") then
		MonDKP:Print("Broadcasting Loot History...")
	elseif (prefix == "MonDKPDKPLogSync") then
		MonDKP:Print("Broadcasting DKP History...")
	end
end