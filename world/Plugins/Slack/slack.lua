
-- queue containing the updates that need to be applied to the minecraft world
UpdateQueue = nil
-- array of container objects
Containers = {}
Calendars = {}
Tasks = {}
-- 
SignsToUpdate = {}

-- as a lua array cannot contain nil values, we store references to this object
-- in the "Containers" array to indicate that there is no container at an index
EmptyContainerSpace = {}

-- Tick is triggered by cPluginManager.HOOK_TICK
function Tick(TimeDelta)
	UpdateQueue:update(MAX_BLOCK_UPDATE_PER_TICK)
end

-- Plugin initialization
function Initialize(Plugin)
	Plugin:SetName("Slack")
	Plugin:SetVersion(1)

	UpdateQueue = NewUpdateQueue()

	-- Hooks

	cPluginManager:AddHook(cPluginManager.HOOK_WORLD_STARTED, WorldStarted);
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_JOINED, PlayerJoined);
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_USING_BLOCK, PlayerUsingBlock);
	cPluginManager:AddHook(cPluginManager.HOOK_CHUNK_GENERATING, OnChunkGenerating);
	cPluginManager:AddHook(cPluginManager.HOOK_PLAYER_FOOD_LEVEL_CHANGE, OnPlayerFoodLevelChange);
	cPluginManager:AddHook(cPluginManager.HOOK_TAKE_DAMAGE, OnTakeDamage);
	cPluginManager:AddHook(cPluginManager.HOOK_SERVER_PING, OnServerPing);
	cPluginManager:AddHook(cPluginManager.HOOK_TICK, Tick);

	-- Command Bindings

	cPluginManager.BindCommand("/nical", "*", NicoCalCommand, " - nico nico calendar CLI commands")
	cPluginManager.BindCommand("/task", "*", TaskTowerCommand, " - task CLI commands")

	Plugin:AddWebTab("Slack",HandleRequest_Slack)

	-- make all players admin
	cRankManager:SetDefaultRank("Admin")

	
	LOG("Initialised " .. Plugin:GetName() .. " v." .. Plugin:GetVersion())

	return true
end

-- updateStats update CPU and memory usage displayed
-- on container sign (container identified by id)
function updateStats(id, mem, cpu)
	for i=1, table.getn(Containers)
	do
		if Containers[i] ~= EmptyContainerSpace and Containers[i].id == id
		then
			Containers[i]:updateMemSign(mem)
			Containers[i]:updateCPUSign(cpu)
			break
		end
	end
end

-- getStartStopLeverContainer returns the container
-- id that corresponds to lever at x,y coordinates
function getStartStopLeverContainer(x, z)
	for i=1, table.getn(Containers)
	do
		if Containers[i] ~= EmptyContainerSpace and x == Containers[i].x + 1 and z == Containers[i].z + 1
		then
			return Containers[i].id
		end
	end
	return ""
end

-- getRemoveButtonContainer returns the container
-- id and state for the button at x,y coordinates
function getRemoveButtonContainer(x, z)
	for i=1, table.getn(Containers)
	do
		if Containers[i] ~= EmptyContainerSpace and x == Containers[i].x + 2 and z == Containers[i].z + 3
		then
			return Containers[i].id, Containers[i].running
		end
	end
	return "", true
end

-- destroyContainer looks for the first container having the given id,
-- removes it from the Minecraft world and from the 'Containers' array
function destroyContainer(id)
	-- loop over the containers and remove the first having the given id
	for i=1, table.getn(Containers)
	do
		if Containers[i] ~= EmptyContainerSpace and Containers[i].id == id
		then
			-- remove the container from the world
			Containers[i]:destroy()
			-- if the container being removed is the last element of the array
			-- we reduce the size of the "Container" array, but if it is not, 
			-- we store a reference to the "EmptyContainerSpace" object at the
			-- same index to indicate this is a free space now.
			-- We use a reference to this object because it is not possible to
			-- have 'nil' values in the middle of a lua array.
			if i == table.getn(Containers)
			then
				table.remove(Containers, i)
				-- we have removed the last element of the array. If the array
				-- has tailing empty container spaces, we remove them as well.
				while Containers[table.getn(Containers)] == EmptyContainerSpace
				do
					table.remove(Containers, table.getn(Containers))
				end
			else
				Containers[i] = EmptyContainerSpace
			end
			-- we removed the container, we can exit the loop
			break
		end
	end
end

-- updateContainer accepts 3 different states: running, stopped, created
-- sometimes "start" events arrive before "create" ones
-- in this case, we just ignore the update
function updateContainer(id,name,imageRepo,imageTag,state)
	LOG("Update container with ID: " .. id .. " state: " .. state)

	-- first pass, to see if the container is
	-- already displayed (maybe with another state)
	for i=1, table.getn(Containers)
	do
		-- if container found with same ID, we update it
		if Containers[i] ~= EmptyContainerSpace and Containers[i].id == id
		then
			Containers[i]:setInfos(id,name,imageRepo,imageTag,state == CONTAINER_RUNNING)
			Containers[i]:display(state == CONTAINER_RUNNING)
			LOG("found. updated. now return")
			return
		end
	end

	-- if container isn't already displayed, we see if there's an empty space
	-- in the world to display the container
	x = CONTAINER_START_X
	index = -1

	for i=1, table.getn(Containers)
	do
		-- use first empty location
		if Containers[i] == EmptyContainerSpace
		then
			LOG("Found empty location: Containers[" .. tostring(i) .. "]")
			index = i
			break
		end
		x = x + CONTAINER_OFFSET_X			
	end

	container = NewContainer()
	container:init(x,CONTAINER_START_Z)
	container:setInfos(id,name,imageRepo,imageTag,state == CONTAINER_RUNNING)
	container:addGround()
	container:display(state == CONTAINER_RUNNING)

	if index == -1
		then
			table.insert(Containers, container)
		else
			Containers[index] = container
	end
end

--
function WorldStarted()
	math.randomseed(os.time())
	LOG("world started")
	month=2
	names = {"user4", "user3", "user2", "user1", "135yshr"}
	calendar=Calendar.new(month)
	for _, name in ipairs(names) do
		calendar:addUser(name)
	end
	calendar:display()
	Calendars[month]=calendar

	days = {1, 2, 3, 4, 5, 8, 9, 10, 12, 15, 16, 17, 18, 19}
	math.randomseed(os.time())
	for _, d in ipairs(days) do
		for _, name in ipairs(names) do
			calendar:updateFeel(name, d, math.random(3)-1)
		end
	end
end

--
function PlayerJoined(Player)
	-- enable flying
	Player:SetCanFly(true)

	-- refresh containers
	LOG("player joined")
end

-- 
function PlayerUsingBlock(Player, BlockX, BlockY, BlockZ, BlockFace, CursorX, CursorY, CursorZ, BlockType, BlockMeta)
	LOG("Using block: " .. tostring(BlockX) .. "," .. tostring(BlockY) .. "," .. tostring(BlockZ) .. " - " .. tostring(BlockType) .. " - " .. tostring(BlockMeta))

	-- lever: 1->OFF 9->ON (in that orientation)
	-- lever
	if BlockType == 69
	then
		containerID = getStartStopLeverContainer(BlockX,BlockZ)
		LOG("Using lever associated with container ID: " .. containerID)

		if containerID ~= ""
		then
			-- stop
			if BlockMeta == 1
			then
				Player:SendMessage("slack stop " .. string.sub(containerID,1,8))
				r = os.execute("goproxy exec?cmd=slack+stop+" .. containerID)
			-- start
			else 
				Player:SendMessage("slack start " .. string.sub(containerID,1,8))
				os.execute("goproxy exec?cmd=slack+start+" .. containerID)
			end
		else
			LOG("WARNING: no slack container ID attached to this lever")
		end
	end

	-- stone button
	if BlockType == 77
	then
		containerID, running = getRemoveButtonContainer(BlockX,BlockZ)

		if running
		then
			Player:SendMessage("A running container can't be removed.")
		else 
			Player:SendMessage("slack rm " .. string.sub(containerID,1,8))
			os.execute("goproxy exec?cmd=slack+rm+" .. containerID)
		end
	end
end


function OnChunkGenerating(World, ChunkX, ChunkZ, ChunkDesc)
	-- override the built-in chunk generator
	-- to have it generate empty chunks only
	ChunkDesc:SetUseDefaultBiomes(false)
	ChunkDesc:SetUseDefaultComposition(false)
	ChunkDesc:SetUseDefaultFinish(false)
	ChunkDesc:SetUseDefaultHeight(false)
	return true
end


function NicoCalCommand(Split, Player)

	if table.getn(Split) > 0
	then

		LOG("Split[1]: " .. Split[1])

		if Split[1] == "/nical"
		then
			if 3 < table.getn(Split)
			then
				if Split[2] == "feel"
				then
					month = tonumber(Split[3])
					day = tonumber(Split[4])
					name = Split[5]
					feel = tonumber(Split[6])

					cal = Calendars[month]
					if cal == nil
					then
						LOG("failed: " .. tostring(month))
						return
					end
					LOG("executed: update_feel " .. tostring(month) .. " " .. name .. " " .. tostring(day) .. " ".. tostring(feel))
					cal:updateFeel(name, day, feel)
				elseif Split[2] == "add"
				then
					month = tonumber(Split[3])
					name = Split[4]
					LOG("executed: add_user " ..  name)
					cal = Calendars[month]
					cal:addUser(name)
				end
			end
		end
	end

	return true
end

function TaskTowerCommand(split, player)
	if table.getn(split) > 0
	then

		LOG("Split[1]: " .. split[1])

		if split[1] == "/task" then
			if 4 < table.getn(split) then
				if split[2] == "add" then
					name = split[3]
					priority = tonumber(split[4])
					cost = tonumber(split[5])

					LOG("/task add " .. name .. " " .. split[4] .. " " .. split[5])

					if Tasks[priority] == nil then
						Tasks[priority] = 0
					else
						Tasks[priority]=Tasks[priority]+1
					end
					task=TaskContainer.new(name, priority, cost)
					task.offset=Tasks[priority]
					task:display()
				end
			end
		end
	end

	return true
end

function HandleRequest_Slack(Request)
	
	content = "[slackclient]"

	if Request.PostParams["action"] ~= nil then

		action = Request.PostParams["action"]

		-- receiving informations about one container
		
		if action == "containerInfos"
		then
			LOG("EVENT - containerInfos")

			name = Request.PostParams["name"]
			imageRepo = Request.PostParams["imageRepo"]
			imageTag = Request.PostParams["imageTag"]
			id = Request.PostParams["id"]
			running = Request.PostParams["running"]

			-- LOG("containerInfos running: " .. running)

			state = CONTAINER_STOPPED
			if running == "true" then
				state = CONTAINER_RUNNING
			end

			updateContainer(id,name,imageRepo,imageTag,state)
		end

		if action == "startContainer"
		then
			LOG("EVENT - startContainer")

			name = Request.PostParams["name"]
			imageRepo = Request.PostParams["imageRepo"]
			imageTag = Request.PostParams["imageTag"]
			id = Request.PostParams["id"]

			updateContainer(id,name,imageRepo,imageTag,CONTAINER_RUNNING)
		end

		if action == "createContainer"
		then
			LOG("EVENT - createContainer")

			name = Request.PostParams["name"]
			imageRepo = Request.PostParams["imageRepo"]
			imageTag = Request.PostParams["imageTag"]
			id = Request.PostParams["id"]

			updateContainer(id,name,imageRepo,imageTag,CONTAINER_CREATED)
		end

		if action == "stopContainer"
		then
			LOG("EVENT - stopContainer")

			name = Request.PostParams["name"]
			imageRepo = Request.PostParams["imageRepo"]
			imageTag = Request.PostParams["imageTag"]
			id = Request.PostParams["id"]

			updateContainer(id,name,imageRepo,imageTag,CONTAINER_STOPPED)
		end

		if action == "destroyContainer"
		then
			LOG("EVENT - destroyContainer")
			id = Request.PostParams["id"]
			destroyContainer(id)
		end

		if action == "stats"
		then
			id = Request.PostParams["id"]
			cpu = Request.PostParams["cpu"]
			ram = Request.PostParams["ram"]

			updateStats(id,ram,cpu)
		end


		content = content .. "{action:\"" .. action .. "\"}"

	else
		content = content .. "{error:\"action requested\"}"

	end

	content = content .. "[/slackclient]"

	return content
end

function OnPlayerFoodLevelChange(Player, NewFoodLevel)
	-- Don't allow the player to get hungry
	return true, Player, NewFoodLevel
end

function OnTakeDamage(Receiver, TDI)
	-- Don't allow the player to take falling damage
	dt_fall = 3
	if Receiver:GetClass() == 'cPlayer' and TDI.DamageType == dt_fall
	then
		return true, Receiver, TDI	
	end
	return false, Receiver, TDI
end

function OnServerPing(ClientHandle, ServerDescription, OnlinePlayers, MaxPlayers, Favicon)
	-- Change Server Description
	ServerDescription = "A Slack client for Minecraft"
	-- Change favicon
	if cFile:IsFile("/srv/logo.png") then
		local FaviconData = cFile:ReadWholeFile("/srv/logo.png")
		if (FaviconData ~= "") and (FaviconData ~= nil) then
			Favicon = Base64Encode(FaviconData)
		end
	end
	return false, ServerDescription, OnlinePlayers, MaxPlayers, Favicon
end				

