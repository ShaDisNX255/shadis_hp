-- Encounter 1
local encounter1 = {
  name               = "Encounter1",
  weight             = 10,
  path               = "/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
  enemies            = {
    { name = "Shrimpy", rank = 6 },
    { name = "Shrimpy", rank = 7 },
    { name = "Shrimpy", rank = 8 },
  },
  obstacles          = {
    { name = "Rock" },
    { name = "Rock" },
  },
  positions          = {
    { 0, 0, 0, 0, 0, 1 },
    { 0, 0, 0, 0, 2, 0 },
    { 0, 0, 0, 0, 3, 0 },
  },
  obstacle_positions = {
    { 0, 0, 1, 0, 0, 0 },
    { 0, 0, 0, 2, 0, 0 },
    { 0, 0, 0, 0, 0, 0 },
  },
  player_positions   = {
    { 0, 0, 0, 0, 0, 0 },
    { 0, 1, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0 },
  },
  tiles              = {
    { 1, 1, 1, 1, 1, 1 },
    { 1, 1, 1, 1, 1, 1 },
    { 1, 1, 1, 1, 1, 1 },
  },
  teams              = {
    { 2, 2, 2, 1, 1, 1 },
    { 2, 2, 2, 1, 1, 1 },
    { 2, 2, 2, 1, 1, 1 },
  },
}

-- Encounter 2
local encounter2 = {
  name               = "Encounter2",
  weight             = 10,
  path               = "/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
  enemies            = {
    { name = "Piranha",  rank = 4 },
    { name = "ColdHead", rank = 1 },
    { name = "Tark",     rank = 1 },
  },
  obstacles          = {
    { name = "Rock" },
  },
  positions          = {
    { 0, 0, 0, 0, 0, 2 },
    { 0, 0, 0, 0, 1, 3 },
    { 0, 0, 0, 0, 0, 0 },
  },
  obstacle_positions = {
    { 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0 },
  },
  player_positions   = {
    { 0, 0, 0, 0, 0, 0 },
    { 0, 1, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0 },
  },
  tiles              = {
    { 1, 1, 1, 1, 1, 1 },
    { 1, 1, 1, 1, 1, 1 },
    { 1, 1, 1, 1, 1, 1 },
  },
  teams              = {
    { 2, 2, 2, 1, 1, 1 },
    { 2, 2, 2, 1, 1, 1 },
    { 2, 2, 2, 1, 1, 1 },
  },
}

-- Encounter 3
local encounter3 = {
  name               = "Encounter3",
  weight             = 10,
  path               = "/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
  enemies            = {
    { name = "SwordyEl", rank = 5 },
    { name = "SwordyEl", rank = 2 },
    { name = "SwordyEl", rank = 8 },
  },
  obstacles          = { },
  positions          = {
    { 0, 0, 0, 0, 3, 0 },
    { 0, 0, 0, 0, 1, 0 },
    { 0, 0, 0, 0, 2, 0 },
  },
  obstacle_positions = {
    { 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0 },
  },
  player_positions   = {
    { 0, 0, 0, 0, 0, 0 },
    { 0, 1, 0, 0, 0, 0 },
    { 0, 0, 0, 0, 0, 0 },
  },
  tiles              = {
    { 1, 1, 1, 1, 1, 1 },
    { 1, 1, 1, 1, 1, 1 },
    { 1, 1, 1, 1, 1, 1 },
  },
  teams              = {
    { 2, 2, 2, 1, 1, 1 },
    { 2, 2, 2, 1, 1, 1 },
    { 2, 2, 2, 1, 1, 1 },
  },
}

local encounter4 = {
    name="Encounter4",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=1,
    enemies={
        {name="IceManPoN",rank=4},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,0},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {12,12,12,1,1,1},
        {12,12,12,1,1,1},
        {12,12,12,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local encounter5 = {
    name="Encounter5",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=20,
    enemies={
        {name="Tark",rank=1},
        {name="Scuttle",rank=1},
        {name="Puffy",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,2},
        {0,0,0,0,1,0},
        {0,0,0,3,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {12,12,12,1,1,1},
        {12,12,12,1,1,1},
        {12,12,12,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local encounter6 = {
    name="Encounter6",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=1,
    enemies={
        {name="ElementMan",rank=1},
        {name="Scuttle",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,2},
        {0,0,0,0,0,1},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {12,12,12,1,1,1},
        {12,12,12,1,1,1},
        {12,12,12,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

local encounter7 = {
    name="Encounter7",
    path="/server/assets/ezlibs-assets/ezencounters/ezencounters.zip",
    weight=20,
    enemies={
        {name="Swordy",rank=3},
        {name="Scuttle",rank=1},
    },
    obstacles={
    },
    positions={
        {0,0,0,0,0,2},
        {0,0,0,0,1,0},
        {0,0,0,0,0,0},
    },
    obstacle_positions={
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
        {0,0,0,0,0,0},
    },
    player_positions={
        {0,0,0,0,0,0},
        {0,1,0,0,0,0},
        {0,0,0,0,0,0},
    },
    tiles={
        {12,12,12,1,1,1},
        {12,12,12,1,1,1},
        {12,12,12,1,1,1},
    },
    teams={
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
        {2,2,2,1,1,1},
    },
}

-- Export both as a list and individually named records.
return {
  list        = { encounter1, encounter2, encounter3, encounter4, encounter5, encounter6, encounter7 },
  encounter1  = encounter1,
  encounter2  = encounter2,
  encounter3  = encounter3,
  encounter4  = encounter4,
  encounter5  = encounter5,
  encounter6  = encounter6,
  encounter7  = encounter7,
}