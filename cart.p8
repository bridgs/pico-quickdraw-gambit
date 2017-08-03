pico-8 cartridge // http://www.pico-8.com
version 8
__lua__

--[[

quickdraw gambit?

platform channels:
  1: ground
  2: invisible walls

hitbox channels:
 1: player swing
 2: enemy bullets
 4: level exit

render layers:
 4: blood
 5: ??
 6: twinkle

axis:
      +y (up)
       |
  -x --+-- +x (right)
(left) |
      -y (down)

how pixels should be drawn:
  [-0.5,0.5)
       |
       v
     +---+---+
     |   |   | <- (0,1]
     +---+---+
     |   |   | <- (-1,0]
     +---+---+
           ^
           |
       [0.5,1.5)
  
]]

local debug_skip_amt=1

-- global vars
local player
local scene
local level_num
local scene_frame
local slow_mo_frames
local freeze_frames
local pause_frames
local slide_frames
local skip_frames=0
local entities
local new_entities
local buttons={}
local button_presses={}
local light_sources={
	{x=63,y=1,intensity=1,max_color=2,fixed_distance=true,radius=10}
}
function noop() end


-- constants
local directions={"left","right","bottom","top"}
local dir_lookup={
	-- axis,size,increment
	left={"x","width",-1},
	right={"x","width",1},
	bottom={"y","height",-1},
	top={"y","height",1}
}
local scenes={}
local color_ramps={
	red={1,2,8,14},
	grey={1,13,6,7},
	brown={1,2,4,15}
}
local levels={
	-- name,update
	{
		"shotgun joe"
	},
	{
		"quickdraw jane"
	},
	{
		"longjohn john"
	}
}
local entity_classes={
	person={
		-- spatial props
		width=3,
		height=5,
		facing=1,
		anti_grav_frames=0,
		-- collision props
		collision_channel=3, -- ground, invisible walls
		standing_platform=nil,
		-- state props
		is_jumping=false,
		is_jumping_upwards=false,
		has_been_hurt=false,
		-- frame data
		bleed_frames=0,
		on_collide=function(self,dir,platform)
			if dir=="bottom" then
				self.standing_platform=platform
				self.is_jumping=false
				self.is_jumping_upwards=false
				self.anti_grav_frames=0
				if self.has_been_hurt then
					self.vx=0
				end
			end
		end,
		bleed=function(self)
			decrement_counter_prop(self,"bleed_frames")
			if self.bleed_frames>0 then
				local ang=self.bleed_frames/40+0.05-rnd(0.12)
				create_entity("blood",{
					x=self.x+1,
					y=self.y+3,
					vx=self.vx/2-self.facing*sin(ang),
					vy=self.vy/2+0.75*cos(ang)
				})
			end
		end,
		on_collide=function(self,dir,platform)
			if dir=="bottom" then
				self.standing_platform=platform
				self.is_jumping=false
				self.is_jumping_upwards=false
				self.anti_grav_frames=0
				if self.has_been_hurt then
					self.vx=0
				end
			end
		end,
		on_hurt=function(self,other)
			self.hurtbox_channel=0
			self.has_been_hurt=true
			self.anti_grav_frames=0
			if other.facing then
				self.facing=-other.facing
			elseif other.vx>0 then
				self.facing=-1
			elseif other.vx<0 then
				self.facing=1
			end
			self.vx=-self.facing
			self.vy=1.5
			self.standing_platform=nil
			self.bleed_frames=10
			pause_frames=max(pause_frames,17)
		end
	},
	player={
		extends="person",
		is_crouching=false,
		slash_frames=0,
		slash_cooldown_frames=0,
		input_dir=0,
		slash_dir=1,
		pose_frames=45,
		hitbox_channel=1,
		hurtbox_channel=6, -- enemy bullets, level exit
		update=function(self)
			decrement_counter_prop(self,"pose_frames")
			decrement_counter_prop(self,"slash_frames")
			decrement_counter_prop(self,"slash_cooldown_frames")
			decrement_counter_prop(self,"anti_grav_frames")
			self.input_dir=ternary(buttons[1],1,0)-ternary(buttons[0],1,0)
			self.is_jumping_upwards=self.is_jumping_upwards and buttons[2]
			if not self.has_been_hurt and self.pose_frames<=0 then
				-- change facing
				if self.slash_frames==0 and self.input_dir!=0 then
					self.facing=self.input_dir
				end
				-- slash
				if self.slash_cooldown_frames==0 and (buttons[4] or buttons[5]) then
					self.slash_dir*=-1
					self.slash_frames=9
					self.slash_cooldown_frames=20
					if self.is_jumping then
						self.vy=0
						self.anti_grav_frames=15
					end
				end
			end
			if not self.has_been_hurt then
				-- move
				if (self.slash_frames>0 and not self.is_jumping) or self.pose_frames>0 then
					self.vx=0
				else
					self.vx=self.input_dir
				end
			end
			-- gravity
			if self.anti_grav_frames>0 then
				self.vy-=0.05
			else
				self.vy-=0.2
			end
			if not self.has_been_hurt then
				-- jump
				if self.standing_platform and buttons[2] and self.pose_frames<=0 then
					self.vy=2.1
					self.is_jumping=true
					self.is_jumping_upwards=true
				end
				-- end jump
				if self.is_jumping and not self.is_jumping_upwards and self.vy==mid(0.6,self.vy,1.8) then
					self.vy=0.6
				end
			end
			-- move/find collisions
			self.standing_platform=nil
			self:apply_velocity()
			-- crouch
			self.is_crouching=self.standing_platform and self.vx==0 and buttons[3] and self.pose_frames<=0
			self.height=ternary(self.is_crouching,4,5)
			self:bleed()
		end,
		draw=function(self)
			-- figure out the correct sprite
			local sprite=0
			if self.has_been_hurt then
				sprite=ternary(self.standing_platform,8,7)
			elseif self.pose_frames>0 and self.pose_frames<45 then
				sprite=ternary(self.pose_frames>40,9,10)
			elseif self.slash_frames>0 then
				sprite=ternary(self.is_jumping and self.vx!=0 and (self.facing>0)==(self.vx>0),7,6)
			elseif self.is_jumping then
				sprite=ternary(self.vx==0,4,5)
			elseif self.is_crouching then
				sprite=1
			elseif self.vx!=0 then
				sprite=2+flr(self.frames_alive/4)%2
			end
			-- draw the sprite
			self:apply_lighting(self.facing<0)
			sspr(8*sprite,0,8,6,self.x-ternary(self.facing<0,2.5,1.5),-self.y-6,8,6,self.facing<0)
			pal()
			-- draw the sword slash
			if self.slash_frames>0 then
				local slash_sprite=({6,6,5,4,4,3,2,1,0})[self.slash_frames]
				sspr(10*slash_sprite,ternary(self.slash_dir<0,15,6),10,9,self.x-ternary(self.facing<0,4.5,1.5),-self.y-7,10,9,self.facing<0)
			end
			-- draw pose schwing
			if self.pose_frames==mid(17,self.pose_frames,30) then
				local pose_sprite=flr(60-(self.pose_frames-18)/2)
				spr(pose_sprite,self.x+ternary(self.facing<0,-5.5,1.5),-self.y-8,1,1,self.facing<0)
			end
		end,
		pose=function(self)
			self.pose_frames=45
			self.is_jumping_upwards=false
			self.slash_frames=0
			self.facing=1
		end,
		check_for_hits=function(self,other)
			return
				self.slash_frames>=4 and
				self.slash_frames<=7 and
				rects_overlapping(
					self.x-ternary(self.facing>0,0,7),self.y-3,10,10,
					other.x,other.y,other.width,other.height)
		end,
		on_hit=function(self)
			self.slash_cooldown_frames=max(0,self.slash_cooldown_frames-10)
		end,
		on_hurt=function(self,other)
			self:super_on_hurt(other)
			self.slash_frames=0
			self.pose_frames=0
		end
	},
	shooter={
		-- name_tag
		extends="person",
		height=6,
		shoot_frames=0,
		hurtbox_channel=1,
		update=function(self)
			decrement_counter_prop(self,"shoot_frames")
			if not self.has_been_hurt and self.frames_alive%30==3 then
				self:shoot()
			end
			self.vy-=0.2
			self.standing_platform=nil
			self:apply_velocity()
			self:bleed()
		end,
		shoot=function(self)
			create_entity("bullet",{x=self.x-4,y=self.y+3})
			self.shoot_frames=6
		end,
		draw=function(self)
			self:apply_lighting()
			local sprite=25
			if self.has_been_hurt then
				sprite=ternary(self.standing_platform,27,26)
			end
			spr(sprite,self.x-2.5,-self.y-7.5)
			pal()
			if self.shoot_frames>0 then
				spr(51-ceil(self.shoot_frames/2),self.x-10.5,self.y-6.5)
			end
		end,
		on_hurt=function(self,other)
			self:super_on_hurt(other)
			self.vy=2
			self.vx=-self.facing/4.5
			self.shoot_frames=0
			self.name_tag:get_slashed()
			create_entity("level_exit")
		end
	},
	level_exit={
		x=124,
		width=2,
		height=15,
		hitbox_channel=4,
		draw=function(self)
			if self.frames_alive>42 and (self.frames_alive-42)%30>10 then
				spr(53,self.x-6.5,-self.y-14)
			end
		end,
		draw_shadow=noop,
		on_hit=function(self)
			self:die()
			return false
		end,
		on_death=function(self)
			freeze_frames=max(freeze_frames,3)
			pause_frames=max(pause_frames,57)
			slide_frames=max(slide_frames,57)
			load_level(level_num+1,112)
			player:pose()
		end
	},
	invisible_wall={
		width=2,
		height=2,
		platform_channel=2,
		is_slide_immune=true,
		draw=noop,
		draw_shadow=noop
	},
	bullet={
		width=2,
		height=1,
		vx=-1,
		hitbox_channel=2,
		hurtbox_channel=1,
		frames_to_death=120,
		on_hurt=function(self)
			self:die()
			create_entity("twinkle",{x=self.x+self.vx,y=self.y+self.vy})
		end
	},
	twinkle={
		frames_to_death=9,
		draw=function(self)
			spr(51+flr(self.frames_alive/3)%2,self.x-2.5,-self.y-5)
		end
	},
	blood={
		render_layer=4,
		update=function(self)
			self.vx*=0.97
			self.vy-=0.1
			self:apply_velocity()
			if self.y<=0 then
				self.y=0
				self.vy=0
				self.vx=0
			end
		end,
		draw=function(self)
			pset(self.x+0.5,-self.y,ternary(self.y<=0,2,8))
		end,
		on_collide=function(self)
			self.collision_channel=0
			self.frames_to_death=30
		end
	},
	name_tag={
		-- x,text
		y=-5,
		top_hidden=false,
		bottom_hidden=false,
		is_pause_immune=true,
		update=function(self)
			if self.frames_to_death>0 then
				if self.frames_to_death==84 then
					self.bottom_hidden=true
					self.vx=1
					create_entity("name_tag",{
						x=self.x-1,
						y=self.y-2,
						vx=-0.5,
						text=self.text,
						top_hidden=true,
						frames_to_death=82
					})
					self.x+=2
				elseif self.frames_to_death<=82 then
					self.vy-=0.2
				end
				self.vx*=0.97
				self:apply_velocity()
			end
		end,
		draw=function(self)
			print(self.text,self.x-4*#self.text+0.5,-self.y,2)
			if self.top_hidden then
				rectfill(self.x-4*#self.text+0.5,-self.y,self.x-1.5,-self.y+2,0)
			elseif self.bottom_hidden then
				rectfill(self.x-4*#self.text+0.5,-self.y+2,self.x-1.5,-self.y+4,0)
			end
		end,
		get_slashed=function(self)
			create_entity("name_tag_slash",{x=self.x-4*#self.text})
			self.frames_to_death=100
		end
	},
	name_tag_slash={
		-- x
		y=-7,
		frames_to_death=17,
		is_pause_immune=true,
		init=function(self)
			self.left_x=self.x-10
			self.right_x=self.x-6
		end,
		update=function(self)
			self.right_x+=mid(0,(self.frames_alive+0.5)/3,1)*(128-self.right_x)
			self.left_x+=mid(0,self.frames_alive/10,1)*(128-self.left_x)
		end,
		draw=function(self)
			if self.x<self.right_x then
				line(self.x+0.5,-self.y,self.right_x+0.5,-self.y,0)
			end
			line(self.left_x+0.5,-self.y,self.right_x+0.5,-self.y,7)
		end
	},
	debug_cube={
		width=8,
		height=8,
		update=function(self)
			self.vx=(ternary(buttons[1],1,0)-ternary(buttons[0],1,0))/5
			self.vy=(ternary(buttons[2],1,0)-ternary(buttons[3],1,0))/5
			self:apply_velocity()
		end
	},
}


-- main functions
function _init()
	local i
	for i=0,5 do
		buttons[i]=false
		button_presses[i]=99
	end
	init_scene("game")
end

function _update()
	-- skip frames
	local will_skip_frame=false
	skip_frames=increment_counter(skip_frames)
	if skip_frames%debug_skip_amt>0 then
		will_skip_frame=true
	-- freeze frames
	elseif freeze_frames>0 then
		freeze_frames=decrement_counter(freeze_frames)
		will_skip_frame=true
	-- pause/slow-mo frames
	else
		pause_frames=decrement_counter(pause_frames)
		if slow_mo_frames>0 then
			slow_mo_frames=decrement_counter(slow_mo_frames)
			will_skip_frame=(slow_mo_frames%4>0)
		end
	end
	-- keep track of inputs (because btnp repeats presses)
	-- todo change buttons[] to button_presses[] which works a little better
	local i
	for i=0,5 do
		if btn(i) and not buttons[i] then
			button_presses[i]=0
		elseif not will_skip_frame then
			increment_counter_prop(button_presses,i)
		end
		buttons[i]=btn(i)
	end
	-- call the update function of the current scene
	if not will_skip_frame then
		scene_frame=increment_counter(scene_frame)
		scenes[scene][2]()
	end
end

function _draw()
	-- reset the canvas
	camera()
	rectfill(0,0,127,127,0)
	-- draw guidelines
	-- color(1)
	-- rect(0,0,63,63)
	-- rect(66,0,127,63)
	-- rect(0,66,63,127)
	-- rect(66,66,127,127)
	-- call the draw function of the current scene
	scenes[scene][3]()
	-- draw debug info
	camera()
	-- print("mem:      "..flr(100*(stat(0)/1024)).."%",2,107,ternary(stat(1)>=922,2,1))
	-- print("cpu:      "..flr(100*stat(1)).."%",2,114,ternary(stat(1)>=.9,2,1))
	-- print("entities: "..#entities,2,121,ternary(#entities>50,2,1))
end


-- game functions
function init_game()
	-- reset everything
	entities,new_entities={},{}
	slide_frames=0
	-- create initial entities
	player=create_entity("player",{x=10})
	create_entity("invisible_wall",{x=-10,y=-2,width=146,platform_channel=1})
	create_entity("invisible_wall",{x=-1,y=-2,height=40})
	create_entity("invisible_wall",{x=125,y=-2,height=40})
	-- load the first level
	load_level(1,0)
	-- immediately add new entities to the game
	add_new_entities()
end

function update_game()
	local entity
	-- slide entities
	slide_frames=decrement_counter(slide_frames)
	if slide_frames>0 then
		for entity in all(entities) do
			if not entity.is_slide_immune then
				entity.x-=2
			end
		end
	end
	-- update entities
	for entity in all(entities) do
		if pause_frames<=0 or entity.is_pause_immune then
			-- call the entity's update function
			entity:update()
			-- do some default update stuff
			increment_counter_prop(entity,"frames_alive")
			if decrement_counter_prop(entity,"frames_to_death") then
				entity:die()
			end
			if entity.x<-10 then
				entity:die()
			end
		end
	end
	-- call each entity's post_update function
	for entity in all(entities) do
		if pause_frames<=0 or entity.is_pause_immune then
			entity:post_update()
		end
	end
	-- check for hits
	local entity2
	for entity in all(entities) do
		for entity2 in all(entities) do
			if pause_frames<=0 or (entity.is_pause_immune and entity2.is_pause_immune) then
				if entity!=entity2 and band(entity.hitbox_channel,entity2.hurtbox_channel)>0 then
					if entity:check_for_hits(entity2) then
						if entity:on_hit(entity2)!=false then
							entity2:on_hurt(entity)
						end
					end
				end
			end
		end
	end
	-- add new entities to the game
	add_new_entities()
	-- remove dead entities from the game
	remove_deceased_entities(entities)
	-- sort entities for rendering
	sort_list(entities,function(a,b)
		return a.render_layer>b.render_layer
	end)
end

function draw_game()
	camera(-1,-70)
	-- draw the sky
	rectfill(0,-20,125,3,9)
	-- draw the sun
	color(10)
	line(63-14, -1, 63+14, -1)
	line(63-13, -2, 63+13, -2)
	line(63-12, -3, 63+12, -3)
	line(63-11, -4, 63+11, -4)
	line(63-9,  -5, 63+9,  -5)
	line(63-7,  -6, 63+7,  -6)
	line(63-4,  -7, 63+4,  -7)
	-- draw the ground
	rectfill(0,0,125,3,4)
	-- draw each entity's shadow
	foreach(entities,function(entity)
		entity:draw_shadow()
		pal()
	end)
	-- draw each entity
	foreach(entities,function(entity)
		entity:draw()
		pal()
	end)
end

function load_level(num,offset)
	level_num=num
	local level=levels[level_num]
	local name_tag=create_entity("name_tag",{
		x=127+offset,
		text=level[1]
	})
	create_entity("shooter",{
		x=113+offset,
		name_tag=name_tag
	})
end


-- entity functions
function create_entity(class_name,args,skip_init)
	local superclass_name,entity,k,v=entity_classes[class_name].extends
	-- this entity might extend another
	if superclass_name then
		entity=create_entity(superclass_name,args,true)
	-- if not, create a default entity
	else
		entity={
			is_alive=true,
			frames_alive=0,
			frames_to_death=0,
			render_layer=5,
			color_ramp=color_ramps.grey,
			is_pause_immune=false,
			is_slide_immune=false,
			-- spatial props
			x=0,
			y=0,
			width=0,
			height=0,
			vx=0,
			vy=0,
			-- collision props
			bounce_x=0,
			bounce_y=0,
			platform_channel=0,
			collision_channel=0,
			-- hit props
			hitbox_channel=0,
			hurtbox_channel=0,
			-- entity methods
			init=noop,
			add_to_game=noop,
			update=function(self)
				self:apply_velocity()
			end,
			post_update=noop,
			draw=function(self)
				self:draw_shape()
			end,
			draw_shadow=function(self)
				local slope=(self.x-62)/15
				local y
				local left=self.x+0.5
				local right=self.x+self.width-0.5
				local bottom=self.y
				local top=self.y+self.height
				for y=0,3 do
					local shadow_left=max(0,left+slope*y+ternary(slope<0 and self.height>1,slope,0))
					local shadow_right=min(right+slope*y+ternary(slope>0 and self.height>1,slope,0),125)
					if bottom<=y and top>y and shadow_left<shadow_right then
						line(shadow_left,y,shadow_right,y,2)
					end
				end
			end,
			draw_outline=function(self)
				rect(self.x+0.5,-self.y-1,self.x+self.width-0.5,-self.y-self.height,12)
				-- rect(self.x+0.5-2,-self.y-1+2,self.x+self.width-0.5+2,-self.y-self.height-2,12)
			end,
			draw_shape=function(self)
				rectfill(self.x+0.5,-self.y-1,self.x+self.width-0.5,-self.y-self.height,self.color_ramp[1])
			end,
			apply_lighting=function(self,flipped)
				local c
				for c=1,3 do
					pal(c,self.color_ramp[c])
				end
				for c=4,15 do
					local surface_x,surface_y=normalize(
						ternary(flipped,3-c%4,c%4)-1.5, -- -1.5,-0.5,0.5,1.5
						2-flr(c/4)) -- -1,0,1
					local lightness=1
					local light_source
					for light_source in all(light_sources) do
						local dx=mid(-100,light_source.x-self.x-self.width/2,100)
						local dy=mid(-100,light_source.y-self.y-self.height/2,100)
						local square_dist=dx*dx+dy*dy -- between 0 and 20000
						local dist=sqrt(square_dist) -- between 0 and ~142
						local dx_norm=dx/dist -- between -1 and 1
						local dy_norm=dy/dist -- between -1 and 1
						local dot=ternary(dist<light_source.radius,1,surface_x*dx_norm+surface_y*dy_norm)
						lightness=mid(1,flr(
							4*dot*
							light_source.intensity*
							ternary(light_source.fixed_distance,1,mid(0.1,35/dist,1.5))),
							light_source.max_color)
					end
					pal(c,self.color_ramp[lightness])
				end
			end,
			die=function(self)
				if self.is_alive then
					self.is_alive=false
					self:on_death()
				end
			end,
			on_death=noop,
			apply_velocity=function(self)
				local vx,vy=self.vx,self.vy
				if vx!=0 or vy!=0 then
					local move_steps,t,entity,dir=ceil(max(abs(vx),abs(vy))/0.25)
					for t=1,move_steps do
						if vx==self.vx then
							self.x+=vx/move_steps
						end
						if vy==self.vy then
							self.y+=vy/move_steps
						end
						if self.collision_channel>0 then
							for dir in all(directions) do
								for entity in all(entities) do
									self:check_for_collision(entity,dir)
								end
							end
						end
						-- if this is a moving obstacle, check to see if it rammed into anything
						if self.platform_channel>0 then
							for entity in all(entities) do
								for dir in all(directions) do
									entity:check_for_collision(self,dir)
								end
							end
						end
					end
				end
			end,
			check_for_collision=function(self,platform,dir)
				local axis=dir_lookup[dir][1] -- e.g. "x"
				local size=dir_lookup[dir][2] -- e.g. "width"
				local vel="v"..axis -- e.g. "vx"
				local bounce="bounce_"..axis -- e.g. "bounce_x"
				local mult=dir_lookup[dir][3] -- e.g. 1
				if band(self.collision_channel,platform.platform_channel)>0 and self!=platform and mult*self[vel]>=mult*platform[vel] and is_overlapping_dir(self,platform,dir) then
					self[axis]=platform[axis]+ternary(mult<0,platform[size],-self[size])
					self[vel]=(platform[vel]-self[vel])*self[bounce]+platform[vel]
					self:on_collide(dir,platform)
				end
			end,
			on_collide=noop,
			check_for_hits=function(self,other)
				return is_overlapping(self,other)
			end,
			on_hurt=function(self)
				self:die()
			end,
			on_hit=function(self)
				self:die()
			end
		}
	end
	-- add class properties/methods onto it
	for k,v in pairs(entity_classes[class_name]) do
		if superclass_name and type(entity[k])=="function" then
			entity["super_"..k]=entity[k]
		end
		entity[k]=v
	end
	-- add properties onto it from the arguments
	for k,v in pairs(args or {}) do
		entity[k]=v
	end
	if not skip_init then
		-- initialize it
		entity:init(args or {})
		-- add it to the list of entities-to-be-added
		add(new_entities,entity)
	end
	-- return it
	return entity
end

function add_new_entities()
	foreach(new_entities,function(entity)
		entity:add_to_game()
		add(entities,entity)
	end)
	new_entities={}
end

function remove_deceased_entities(list)
	filter_list(list,function(entity)
		return entity.is_alive
	end)
end


-- scene functions
function init_scene(s)
	scene,scene_frame,slow_mo_frames,freeze_frames,pause_frames=s,0,0,0,0
	scenes[scene][1]()
end


-- helper functions
function ceil(n)
	return -flr(-n)
end

-- if condition is true return the second argument, otherwise the third
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

-- gets the character in string s at position n
function char_at(s,n)
	return sub(s,n,n)
end

-- gets the first position of character c in string s
function char_index(s,c)
	local i
	for i=1,#s do
		if char_at(s,i)==c then
			return i
		end
	end
end

-- generates a random integer between min_val and max_val, inclusive
function rnd_int(min_val,max_val)
	return flr(min_val+rnd(1+max_val-min_val))
end

function normalize(x,y)
	local len=sqrt(x*x+y*y)
	return x/len,y/len
end

-- if n is below min, wrap to max. if n is above max, wrap to min
function wrap(min_val,n,max_val)
	return ternary(n<min_val,max_val,ternary(n>max_val,min_val,n))
end

-- increment a counter, wrapping to 20000 if it risks overflowing
function increment_counter(n)
	if n>32000 then
		return 20000
	end
	return n+1
end

-- increment_counter on a property on an object
function increment_counter_prop(obj,k)
	obj[k]=increment_counter(obj[k])
end

-- decrement a counter but not below 0
function decrement_counter(n)
	return max(0,n-1)
end

-- decrement_counter on a property of an object, returns true when it reaches 0
function decrement_counter_prop(obj,k)
	if obj[k]>0 then
		obj[k]=decrement_counter(obj[k])
		return obj[k]<=0
	end
	return false
end

-- washes all non-black colors to c
function colorwash(c)
	local i
	for i=1,15 do
		pal(i,c)
	end
end

-- sorts list (inefficiently) based on func
function sort_list(list,func)
	local i
	for i=1,#list do
		local j=i
		while j>1 and func(list[j-1],list[j]) do
			list[j],list[j-1]=list[j-1],list[j]
			j-=1
		end
	end
end

-- filters list to contain only entries where func is truthy
function filter_list(list,func)
	local num_deleted,i=0
	for i=1,#list do
		if not func(list[i]) then
			list[i]=nil
			num_deleted+=1
		else
			list[i-num_deleted],list[i]=list[i],nil
		end
	end
end


-- hit detection functions
function is_overlapping(a,b)
	if not a or not b then
		return false
	end
	return rects_overlapping(
		a.x,a.y,a.width,a.height,
		b.x,b.y,b.width,b.height)
end

function is_overlapping_dir(a,b,dir)
	if not a or not b then
		return false
	end
	local a_sub={
		x=a.x+0.3,
		y=a.y+0.3,
		width=a.width-0.6,
		height=a.height-0.6
	}
	local axis,size=dir_lookup[dir][1],dir_lookup[dir][2]
	a_sub[axis]=a[axis]+ternary(dir_lookup[dir][3]>0,a[size]/2,0)
	a_sub[size]=a[size]/2
 	return rects_overlapping(
 		a_sub.x,a_sub.y,a_sub.width,a_sub.height,
 		b.x,b.y,b.width,b.height)
end

-- check for aabb overlap
function rects_overlapping(x1,y1,w1,h1,x2,y2,w2,h2)
	return x1+w1>=x2 and x2+w2>=x1 and y1+h1>=y2 and y2+h2>=y1
end

-- set up the scenes now that the functions are defined
scenes={
	game={init_game,update_game,draw_game}
}


__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00047000000000000000470000008b000008b00000008b0000047000004700000000000000047000000470000800080008000800080008000800080008000800
0081b0000004700000041b0000081b000081b00000081b000004b0000041b000000000000081b0000081b1110080800000808000008080000080800000808000
1111b0000081b00011111b0011111b001111b00011111b000081b0000081b000000000000081110000811f000008000000080000000800000008000000080000
0081b0001111b0000081f0000081f00000cee00000cdf000008eb0000081f000044770000081b0000081b0000080800000808000008080000080800000808000
00c0f0000c11f0000800f00000cf00000c000f000c0f000000c0f00000080f0008111b0000c0f00000c0f0000800080008000800080008000800080008000800
00000000000000000000000000000000000001000000777000000077700000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000017700177777770007777777000770000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000177700017777770017777777000770000008800000000000000000000000000000000000000000000000000000000
07000000000000000000000001110000007777770001777777070077777717700000008800000000000000000000000008000800080008000800080008000800
77110000000700010000000000071100007777770700077777070000777707000000008800045700000045700000000000808000008080000080800000808000
110000000007770100000000077777000077777707700077770000000007070000000088008111b00008111b0000000000080000000800000008000000080000
00000000000077771000000777777000007777700077700770000000000000700000008811081b00000081b00000000000808000008080000080800000808000
00000000000077771000007777777000077777700007770070000770000000000007008801081b00000811b00000070008000800080008000800080008000800
0000000000000077700000007770000000777000000007700000007770000000007000880008db0000081b000044417000000000000000000000000000000000
000000000000000000000000777000000077700000007707000000777000000077700088000c0f0000c0f000081111b000000000000000000000000000000000
01000000000000771000007777777000000777700007700770007700000000000000008800000000000000000000000000000000000000000000000000000000
07100000000077710000000777777000000777700077707770007000000000000000008808000800080008000800080008000800080008000800080008000800
07710000000077710000000007771100000777770077007777070000000700100000008800808000008080000080800000808000008080000080800000808000
07000000000770100000000001110000000777770770077777001000007701000000008800080000000800000008000000080000000800000008000000080000
00000000000000000000000000000000001777770770177777010000077717000000008800808000008080000080800000808000008080000080800000808000
00000000000000000000000000000000000177700701777770177007777000700000008808000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000017700017777770007777777000777000008800000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000070000000777000000077700000007770008800000000000000000000000000000000000000000000000000000000
000000000000000000000a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000a00000000000000000000000000088800000000000000000000000000000000700000000000000000000000000080008000800080008000800
00000aa00000000a00000000000f0000000000000880880000000000000000000000700000000700000000700000000000000000008080000080800000808000
0000aaaa00000aaa00000000000f0000000700008880888000000000000000000000700000007700000707000000f00000000000000800000008000000080000
00000aa00000000a0000000000fff000777077708880888807700000007770000007770000777770000070000007770000007000008080000080800000808000
00000000000000a000000000000f0000000700008888888000000000000000000000700000077000000707000000f00000000000080008000800080008000800
000000000000000000000a00000f0000000000000880880000000000000000000000700000070000007000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000088800000000000000000000000000000070000000000000000000000000000000000000000000000000000
01000100000000000100010000000000004567000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
10000010000000001000001000000000045116700800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
10000010000000001000001000000000441111770080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
11005116000000001100111100000000891111ab0008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
01455166000000000111111100000000891111ab0080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
044911a7700000000111111110000000cc1111ff0800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
8899111aa700000011111111110000000cd11ef00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
8889911aab000000111111111100000000cdef000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
008cddeffb0000000011111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c0d0f0b0000000001010101000000080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00000000000000000000000000000000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00000000000000000000000000000000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00000000000000000000000000000000080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
00080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000000800000008000000080000
00808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000008080000080800000808000
08000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800080008000800
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
010600003063030630306302463024620246202f0002f0002d0002d0052d0002d00500000000002d0002d0002b0002b0052b0002b00500000000002b0002b0002a0002a0002a0002a000300002f0002d0002b000
01060000215502b5512b5512b5412b5310d5012900026000215002b5012b5012b5012b5012b50128000240002900024000280000000000000000000000000000000000000000000000000000000000000002d000
0106000021120211151d1201d1152d000280002d0002f000300002f0002d0002b000290002800000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f000
010300001c7301c730186043060524600182001830018300184001840018500185001860018600187001870018200182000000000000000000000000000000000000000000000000000000000000000000000000
010300001873018730000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0106000024540245302b5202b54013630136111360100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01060000186701865018620247702b7702b7700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010c0000185551c5551f5501f55000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010600000c2200c2210c2110c21100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000003065024631186210c61100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344

